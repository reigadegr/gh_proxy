#!/bin/sh
# 生成 CA 证书 + 服务器证书
# CA 证书放系统信任链，服务器证书给程序用
# apt install openssl openssl-tool

# ========== 1. 生成 CA 证书（自签名） ==========
openssl ecparam -genkey -name prime256v1 -out keys/ca_key.pem

cat > keys/ca.cnf <<EOF
[req]
distinguished_name = req_dn
x509_extensions = v3_ext
prompt = no

[req_dn]
CN = GitHub Proxy CA

[v3_ext]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
EOF

openssl req -new -x509 -key keys/ca_key.pem -out keys/ca_cert.pem \
    -days 3650 -config keys/ca.cnf

# ========== 2. 生成服务器证书（由 CA 签发） ==========
openssl ecparam -genkey -name prime256v1 -out keys/private_key.pem

cat > keys/server.cnf <<EOF
[req]
distinguished_name = req_dn
req_extensions = v3_req
prompt = no

[req_dn]
CN = github.com

[v3_req]
subjectAltName = DNS:github.com, DNS:*.github.com
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
EOF

# 生成 CSR
openssl req -new -key keys/private_key.pem -out keys/server.csr -config keys/server.cnf

# 用 CA 签发服务器证书
openssl x509 -req -in keys/server.csr -CA keys/ca_cert.pem -CAkey keys/ca_key.pem \
    -CAcreateserial -out keys/cert.pem -days 3650 \
    -extfile keys/server.cnf -extensions v3_req

# ========== 3. 清理临时文件 ==========
rm -f keys/ca.cnf keys/server.cnf keys/server.csr keys/ca_key.pem keys/ca_cert.srl

echo "[✓] 生成完成:"
echo "  keys/ca_cert.pem   -> 放系统信任链（KSU 模块）"
echo "  keys/cert.pem      -> 服务器证书（程序使用）"
echo "  keys/private_key.pem -> 服务器私钥（程序使用）"
