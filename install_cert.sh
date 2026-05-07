#!/data/data/com.termux/files/usr/bin/bash
# Install gh_proxy CA cert into Android system trust store via KernelSU/Magisk module
# Systemless approach — no actual /system modification

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_SRC="$SCRIPT_DIR/keys/ca_cert.pem"
MODULE_ID="gh_proxy"
MODULE_DIR="/data/adb/modules/$MODULE_ID"
CACERTS_DIR="$MODULE_DIR/system/etc/security/cacerts"
TERMUX_CERTS="$PREFIX/etc/tls/certs"

# Check cert exists
if [ ! -f "$CERT_SRC" ]; then
    echo "[!] ca_cert.pem not found at $CERT_SRC"
    echo "    Run gen_cert.sh first."
    exit 1
fi

# Compute OpenSSL hash locally in Termux
HASH=$(openssl x509 -inform PEM -subject_hash_old -noout -in "$CERT_SRC")
if [ -z "$HASH" ]; then
    echo "[!] Failed to compute cert hash"
    exit 1
fi
echo "[*] Cert hash: $HASH"

# Create module structure via su
# su -c "rm -rf '$MODULE_DIR' && mkdir -p '$CACERTS_DIR'"

# Copy cert to Magisk/KernelSU module (system trust store)
su -c "cp -af '$CERT_SRC' '$CACERTS_DIR/${HASH}.0' && chmod 644 '$CACERTS_DIR/${HASH}.0'"

# Copy cert to Termux trust store (Termux OpenSSL doesn't read system certs)
su -c "cp -af '$CERT_SRC' '$TERMUX_CERTS/${HASH}.0' && chmod 644 '$TERMUX_CERTS/${HASH}.0'"

echo "[✓] Installed to:"
echo "  System:  $CACERTS_DIR/${HASH}.0"
echo "  Termux:  $TERMUX_CERTS/${HASH}.0"
echo ""
echo "[*] Reboot to activate system cert."
echo ""
echo "To uninstall later:"
echo "  su -c 'rm -rf $MODULE_DIR' && reboot"
echo "  rm -f $TERMUX_CERTS/${HASH}.0"
