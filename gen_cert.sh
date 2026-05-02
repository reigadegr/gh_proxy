#!/bin/sh
# 安装
# apt install openssl openssl-tool

# 生成私钥
openssl genpkey -algorithm ED25519 -out keys/private_key.pem

# 创建临时配置文件，添加 SAN
cat > keys/cert.cnf <<EOF
[req]
distinguished_name = req_dn
x509_extensions = v3_ext
prompt = no

[req_dn]
CN = github.com

[v3_ext]
subjectAltName = DNS:github.com
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
EOF

# 从私钥生成自签名证书
openssl req -new -x509 -key keys/private_key.pem -out keys/cert.pem \
    -days 3650 -config keys/cert.cnf

rm -f keys/cert.cnf
