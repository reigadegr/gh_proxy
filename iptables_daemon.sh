#!/bin/sh
# GitHub 代理 iptables 守护进程
# 定期解析 github.com IP，通过 DNAT 转发到本机代理
# 用法: su -c "sh iptables_daemon.sh"


DIG=$(command -v dig 2>/dev/null || echo /data/data/com.termux/files/usr/bin/dig)
NSLOOKUP=$(command -v nslookup 2>/dev/null || echo /data/data/com.termux/files/usr/bin/nslookup)

PROXY_ADDR="127.0.0.1:443"
CHAIN_NAME="GH_PROXY"
INTERVAL=60

cleanup() {
    echo "[*] 正在清理 iptables 规则..."
    iptables -t nat -D OUTPUT -p tcp --dport 443 -j "$CHAIN_NAME" 2>/dev/null || true
    iptables -t nat -F "$CHAIN_NAME" 2>/dev/null || true
    iptables -t nat -X "$CHAIN_NAME" 2>/dev/null || true
    echo "[✓] 已清理"
    exit 0
}

trap cleanup TERM INT HUP

# 创建自定义链（已存在则忽略报错）
iptables -t nat -N "$CHAIN_NAME" 2>/dev/null || iptables -t nat -F "$CHAIN_NAME"

# 挂载到 OUTPUT（已存在则忽略）
iptables -t nat -C OUTPUT -p tcp --dport 443 -j "$CHAIN_NAME" 2>/dev/null || \
    iptables -t nat -A OUTPUT -p tcp --dport 443 -j "$CHAIN_NAME"

# 排除本机代理进程自身的出站流量，防止回环
iptables -t nat -C "$CHAIN_NAME" -p tcp -d 127.0.0.1 --dport 443 -j RETURN 2>/dev/null || \
    iptables -t nat -I "$CHAIN_NAME" 1 -p tcp -d 127.0.0.1 --dport 443 -j RETURN
# 排除到 lgithub.xyz 的流量（避免代理回环）
PROXY_UPSTREAM_IPS=$("$DIG" +short lgithub.xyz A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
for ip in $PROXY_UPSTREAM_IPS; do
    iptables -t nat -C "$CHAIN_NAME" -p tcp -d "$ip" --dport 443 -j RETURN 2>/dev/null || \
        iptables -t nat -I "$CHAIN_NAME" 1 -p tcp -d "$ip" --dport 443 -j RETURN
done

echo "[✓] 守护进程启动，每 ${INTERVAL}s 刷新一次"

while true; do
    # 解析 github.com IP（兼容 dig 和 nslookup）
    if command -v "$DIG" >/dev/null 2>&1; then
        IPS=$("$DIG" +short github.com A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    else
        IPS=$("$NSLOOKUP" github.com 2>/dev/null | awk '/^Address:/{ip=$2} /^[^[:space:]].*Address:/{print ip}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        # 备用解析
        if [ -z "$IPS" ]; then
            IPS=$("$NSLOOKUP" github.com 2>/dev/null | grep -A1 'Name:' | awk '/Address:/{print $2}' | grep -E '^[0-9]+\.')
        fi
    fi

    if [ -z "$IPS" ]; then
        echo "[!] DNS 解析失败，跳过本轮"
        sleep "$INTERVAL"
        continue
    fi

    # 清空旧规则，重新填充
    iptables -t nat -F "$CHAIN_NAME"

    # 重新添加防回环规则
    iptables -t nat -A "$CHAIN_NAME" -p tcp -d 127.0.0.1 --dport 443 -j RETURN
    UPSTREAM_IPS=$("$DIG" +short lgithub.xyz A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    for uip in $UPSTREAM_IPS; do
        iptables -t nat -A "$CHAIN_NAME" -p tcp -d "$uip" --dport 443 -j RETURN
    done

    NEW_COUNT=0
    for ip in $IPS; do
        iptables -t nat -A "$CHAIN_NAME" -p tcp -d "$ip" --dport 443 -j DNAT --to-destination "$PROXY_ADDR"
        NEW_COUNT=$((NEW_COUNT + 1))
    done

    echo "[$(date '+%H:%M:%S')] 已更新 ${NEW_COUNT} 条规则: $(echo "$IPS" | tr '\n' ' ')"

    sleep "$INTERVAL"
done
