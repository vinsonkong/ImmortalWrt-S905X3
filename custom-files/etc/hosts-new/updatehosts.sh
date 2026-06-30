#!/bin/bash

# === 配置区 ===
HOSTS_FILE="/etc/hosts-new/hosts.combined"        # ✅ 标准路径，必须位于 /etc/
LOG_FILE="/var/log/hosts-update.log"
LOCK_FILE="/tmp/hosts-update.lock"

# 多源 hosts 文件 URL 列表（优先使用国内可访问镜像）
HOSTS_SOURCES=(
    "https://hosts.gitcdn.top/hosts.txt"
    "https://raw.hellogithub.com/hosts"
    "https://raw.githubusercontent.com/maxiaof/github-hosts/master/hosts"  # ✅ 替代 StevenBlack，更稳定
)

# === 日志函数 ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    logger -t "hosts-update" "$1"  # ✅ 使用 logger 写入系统日志
}

# === 锁机制：防止并发执行 ===
if [ -f "$LOCK_FILE" ]; then
    log "❌ 锁文件存在，脚本已在运行，跳过本次更新"
    exit 1
fi
trap "rm -f $LOCK_FILE" EXIT
touch "$LOCK_FILE"

# === 创建 hosts 存储目录 ===
if [ -z "$HOSTS_FILE" ]; then
    echo "Error: HOSTS_FILE is not set."
    exit 1
fi
mkdir -p "$(dirname "$HOSTS_FILE")"

# === 遍历下载并合并所有 hosts 源 ===
TEMP_FILE=$(mktemp)
for source in "${HOSTS_SOURCES[@]}"; do
    log "📥 正在下载: $source"
    curl -sL --connect-timeout 10 --max-time 30 "$source" >> "$TEMP_FILE"
    if [ $? -ne 0 ]; then
        log "⚠️ 下载失败: $source"
    fi
done

# === 去重、过滤空行与注释行 ===
awk 'NF && !/^#/ && !/^$/ { print }' "$TEMP_FILE" | sort -u > "$HOSTS_FILE"
rm -f "$TEMP_FILE"

# === 检查文件是否为空 ===
if [ ! -s "$HOSTS_FILE" ]; then
    log "❌ 合并后的 hosts 文件为空，终止更新"
    exit 1
fi

# === 检查是否已添加该路径到 dnsmasq ===
if ! uci show dhcp | grep -q "addnhosts='$HOSTS_FILE'"; then
    log "✅ 正在设置 addnhosts 路径: $HOSTS_FILE"
    uci add_list dhcp.@dnsmasq[0].addnhosts="$HOSTS_FILE"  # ✅ 明确指定第一个 dnsmasq 实例
    uci commit dhcp
else
    log "ℹ️ 路径已存在，跳过 uci 修改"
fi

# === 重启 dnsmasq 服务 ===
log "🔄 重启 dnsmasq 服务"
/etc/init.d/dnsmasq restart

# === 验证服务状态 ===
if /etc/init.d/dnsmasq status > /dev/null 2>&1; then
    log "✅ 更新成功，dnsmasq 运行正常"
else
    log "❌ dnsmasq 启动失败，请检查配置"
fi

log "🎉 多源 hosts 更新完成"
