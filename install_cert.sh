#!/data/data/com.termux/files/usr/bin/bash
# Install gh_proxy CA cert into Android system trust store via KernelSU/Magisk module
# Systemless approach — no actual /system modification

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_SRC="$SCRIPT_DIR/keys/cert.pem"
MODULE_ID="gh_proxy"
MODULE_DIR="/data/adb/modules/$MODULE_ID"
CACERTS_DIR="$MODULE_DIR/system/etc/security/cacerts"

# Check cert exists
if [ ! -f "$CERT_SRC" ]; then
    echo "[!] cert.pem not found at $CERT_SRC"
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

# Copy cert as {hash}.0
su -c "cp -af '$CERT_SRC' '$CACERTS_DIR/${HASH}.0' && chmod 644 '$CACERTS_DIR/${HASH}.0'"

echo "[✓] Module installed at $MODULE_DIR"
echo "[*] Cert: $CACERTS_DIR/${HASH}.0"
echo "[*] Reboot to activate."
echo ""
echo "To uninstall later:"
echo "  su -c 'rm -rf $MODULE_DIR' && reboot"
