#!/bin/sh
# === 配置区 ===
TARGET_IP="223.5.5.5"
UPSTREAM_IF="wwan"
IFACES="wifinet1 wifinet2 wifinet3"
LOG_FILE="/tmp/wifi_switch.log"
LOCK_FILE="/var/run/wifi_switch.lock"
WAIT_IP_TIMEOUT=25

# === 锁机制 ===
[ -f "$LOCK_FILE" ] && exit 0
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# === 日志(限制8KB) ===
log_msg() {
    echo "$(date '+%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
    [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt 8192 ] && \
        tail -n 30 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
}

# === 外网检测(绑定源IP) ===
check_internet() {
    local src_ip
    src_ip=$(ubus call network.interface."$UPSTREAM_IF" status 2>/dev/null | \
             grep '"address"' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    [ -z "$src_ip" ] && return 1
    ping -I "$src_ip" -c 2 -W 3 "$TARGET_IP" >/dev/null 2>&1
}

# === 获取当前启用接口 ===
get_current() {
    for i in $IFACES; do
        dis=$(uci get wireless."$i".disabled 2>/dev/null)
        [ "$dis" != "1" ] && [ "$dis" != "true" ] && { echo "$i"; return; }
    done
    echo "wifinet1"
}

# === 获取下一个接口(环形轮询) ===
get_next() {
    local curr="$1" found=0 next="" first=""
    for i in $IFACES; do
        [ -z "$first" ] && first="$i"
        [ "$found" = "1" ] && { next="$i"; break; }
        [ "$i" = "$curr" ] && found=1
    done
    echo "${next:-$first}"
}

# === 等待上游接口获取IP ===
wait_for_connection() {
    local elapsed=0 status_json
    while [ "$elapsed" -lt "$WAIT_IP_TIMEOUT" ]; do
        status_json=$(ubus call network.interface."$UPSTREAM_IF" status 2>/dev/null)
        if echo "$status_json" | grep -q '"up": true' && \
           echo "$status_json" | grep '"address"' | grep -qE '([0-9]{1,3}\.){3}[0-9]{1,3}'; then
            return 0
        fi
        sleep 2; elapsed=$((elapsed + 2))
    done
    return 1
}

# === 主逻辑 ===
if check_internet; then
    log_msg "✅ 网络($UPSTREAM_IF)畅通，无需切换"
    exit 0
fi

log_msg "⚠️ 外网断开，开始切换热点..."
curr_iface=$(get_current)
set -- $IFACES; max_tries=$#; tries=0

while [ "$tries" -lt "$max_tries" ]; do
    next_iface=$(get_next "$curr_iface")
    log_msg "🔄 切换: $curr_iface -> $next_iface"

    # UCI批量切换
    for i in $IFACES; do
        uci set wireless."$i".disabled="$([ "$i" = "$next_iface" ] && echo 0 || echo 1)"
    done
    uci commit wireless

    # 重启WiFi(先down释放资源)
    wifi down; sleep 2; wifi up

    log_msg "⏳ 等待 $next_iface 获取IP..."
    if wait_for_connection; then
        log_msg "✅ $next_iface 已获IP，检测外网..."
        sleep 3
        if check_internet; then
            log_msg "🎉 成功！外网恢复(当前:$next_iface)"
            exit 0
        fi
        log_msg "❌ $next_iface 有IP无外网，继续..."
    else
        log_msg "❌ $next_iface 连接超时，继续..."
    fi

    curr_iface="$next_iface"
    tries=$((tries + 1))
done

log_msg "🛑 所有热点已尝试，仍无法联网，等待下次巡检"
exit 0
