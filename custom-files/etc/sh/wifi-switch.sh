#!/bin/sh

# ======= 配置区 ==========
# 测试外网的目标
TARGET_IP="223.5.5.5"
# 上游网络逻辑接口名称
UPSTREAM_IF="wwan"
# 热点列表（必须与 /etc/config/wireless 中的 section 名称一致）
IFACES="wifinet1 wifinet2 wifinet3"
# 日志文件路径
LOG_FILE="/tmp/wifi_switch.log"
# 防并发锁文件
LOCK_FILE="/var/run/wifi_switch.lock"
# 等待上游接口获取IP的最大超时时间(秒)
WAIT_IP_TIMEOUT=25
# ==========================================

# 1. 防并发锁 (防止Cron重复拉起导致网络接口崩溃)
if [ -f "$LOCK_FILE" ]; then
    exit 0
fi
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# 2. 日志处理 (防溢出，限制在 8KB 以内)
log_msg() {
    echo "$(date '+%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
    if [ -f "$LOG_FILE" ] && [ $(wc -c < "$LOG_FILE") -gt 8192 ]; then
        tail -n 30 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

# 3. 外网检测
check_internet() {
    # 获取逻辑接口(wwan)对应的真实 IPv4 地址
    local src_ip=$(ubus call network.interface.$UPSTREAM_IF status 2>/dev/null | grep '"address"' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    
    # 如果没有获取到 IP，说明接口未连接，直接判定为断网
    if [ -z "$src_ip" ]; then
        return 1
    fi

    # 使用真实 IP 作为源地址进行 ping
    ping -I "$src_ip" -c 2 -W 3 "$TARGET_IP" >/dev/null 2>&1
    return $?
}

# 4. 获取当前启用的接口
get_current() {
    for i in $IFACES; do
        dis=$(uci get wireless.$i.disabled 2>/dev/null)
        if [ "$dis" != "1" ] && [ "$dis" != "true" ]; then
            echo "$i"
            return
        fi
    done
    echo "wifinet1" # 兜底默认
}

# 5. 获取列表中的下一个接口
get_next() {
    curr=$1
    found=0
    next=""
    first=""
    for i in $IFACES; do
        [ -z "$first" ] && first=$i
        if [ "$found" = "1" ]; then
            next=$i
            break
        fi
        [ "$i" = "$curr" ] && found=1
    done
    [ -z "$next" ] && next=$first
    echo "$next"
}

# 6. 等待上游接口连接成功 (✅ 同步修复：摒弃 jsonfilter，改用 grep 检测状态和IP)
wait_for_connection() {
    local elapsed=0
    while [ $elapsed -lt $WAIT_IP_TIMEOUT ]; do
        # 获取当前接口状态 JSON
        local status_json=$(ubus call network.interface.$UPSTREAM_IF status 2>/dev/null)
        
        # 检查接口是否 up
        local is_up=$(echo "$status_json" | grep -c '"up": true')
        # 检查是否获取到 IPv4 地址 (复用您的成功命令)
        local has_ip=$(echo "$status_json" | grep '"address"' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
        
        if [ "$is_up" -gt 0 ] && [ -n "$has_ip" ]; then
            return 0 # 成功获取到IP
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1 # 超时未获取到IP
}

# ====== 主逻辑 ============

# 步骤 1：检测当前网络是否能联外网
if check_internet; then
    log_msg "当前网络 ($UPSTREAM_IF) 畅通，无需切换。"
    exit 0
fi

log_msg "⚠️ 外网断开，开始尝试切换热点..."

# 步骤 2：进入切换循环 (最大尝试次数 = 热点列表数量)
set -- $IFACES
MAX_TRIES=$#
TRIES=0
curr_iface=$(get_current)

while [ $TRIES -lt $MAX_TRIES ]; do
    next_iface=$(get_next $curr_iface)
    log_msg "🔄 尝试切换: $curr_iface -> $next_iface"

    # 修改 UCI 配置
    for i in $IFACES; do
        if [ "$i" = "$next_iface" ]; then
            uci set wireless.$i.disabled='0'
        else
            uci set wireless.$i.disabled='1'
        fi
    done
    uci commit wireless

    # 重启 WiFi (防崩溃机制：必须先 down 释放资源)
    wifi down
    sleep 2
    wifi up

    # 步骤 3：等待连接成功 (检测上游接口IP)
    log_msg "⏳ 等待 $next_iface ($UPSTREAM_IF) 获取IP..."
    if wait_for_connection; then
        log_msg "✅ $next_iface 已连接并获取IP，检测外网..."
        
        # 步骤 4：再次检测外网
        sleep 3 # 给路由表和 DNS 一点更新时间
        if check_internet; then
            log_msg "🎉 成功！外网已恢复 (当前: $next_iface)"
            exit 0
        else
            log_msg "❌ $next_iface 有IP但无外网，继续切换..."
        fi
    else
        log_msg "❌ $next_iface 连接超时(未获取IP/密码错误/不在范围)，继续切换..."
    fi

    curr_iface=$next_iface
    TRIES=$((TRIES + 1))
done

log_msg "🛑 列表中所有热点均已尝试，依然无法联网。退出脚本，等待下次定时巡检。"
exit 0
