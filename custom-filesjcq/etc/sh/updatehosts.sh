#!/bin/bash

# === 配置区 ===
HOSTS_FILE="/etc/hosts-new/hosts.combined"        # ✅ 标准路径，必须位于 /etc/
LOG_FILE="/var/log/hosts-update.log"              # ⚠️ OpenWrt 下 /var 为 tmpfs，重启后日志丢失；如需持久化请改为 /root/ 或 /etc/
LOCK_FILE="/tmp/hosts-update.lock"

# 多源 hosts 文件 URL 列表（优先使用国内可访问镜像）
HOSTS_SOURCES=(
    "https://hosts.gitcdn.top/hosts.txt"
    "https://raw.hellogithub.com/hosts"
    "https://raw.githubusercontent.com/maxiaof/github-hosts/master/hosts"
)

# === 日志函数 ===
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    logger -t "hosts-update" "$1"
}

# === 锁机制：防止并发执行 ===
if [ -f "$LOCK_FILE" ]; then
    # 检查锁文件是否超过 1 小时，防止异常残留
    lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
    if [ "$lock_age" -gt 3600 ]; then
        log "⚠️ 检测到过期锁文件（${lock_age}s），强制清除"
        rm -f "$LOCK_FILE"
    else
        log "❌ 锁文件存在且未过期，脚本已在运行，跳过本次更新"
        exit 1
    fi
fi
trap "rm -f '$LOCK_FILE'" EXIT
touch "$LOCK_FILE"

# === 校验 HOSTS_FILE 变量 ===
if [ -z "$HOSTS_FILE" ]; then
    echo "Error: HOSTS_FILE is not set." >&2
    exit 1
fi

# === 创建 hosts 存储目录 ===
mkdir -p "$(dirname "$HOSTS_FILE")" || {
    log "❌ 无法创建目录: $(dirname "$HOSTS_FILE")"
    exit 1
}

# === 遍历下载并合并所有 hosts 源 ===
TEMP_FILE=$(mktemp) || {
    log "❌ 无法创建临时文件"
    exit 1
}

download_success=0
for source in "${HOSTS_SOURCES[@]}"; do
    log "📥 正在下载: $source"
    if curl -sL --connect-timeout 10 --max-time 30 --fail "$source" >> "$TEMP_FILE"; then
        download_success=$((download_success + 1))
        log "✅ 下载成功: $source"
    else
        log "⚠️ 下载失败: $source"
    fi
done

# 至少需要一个源下载成功
if [ "$download_success" -eq 0 ]; then
    log "❌ 所有 hosts 源均下载失败，终止更新"
    rm -f "$TEMP_FILE"
    exit 1
fi

# === 去重、过滤空行与注释行 ===
awk 'NF && !/^#/ && !/^$/ { print }' "$TEMP_FILE" | sort -u > "$HOSTS_FILE"
rm -f "$TEMP_FILE"

# === 检查文件是否为空 ===
if [ ! -s "$HOSTS_FILE" ]; then
    log "❌ 合并后的 hosts 文件为空，终止更新"
    exit 1
fi

line_count=$(wc -l < "$HOSTS_FILE")
log "ℹ️ 合并完成，共 ${line_count} 条有效记录"

# === 安全设置 dnsmasq addnhosts（防止重复添加）===
# 动态获取第一个 dnsmasq 实例的 section 名称
section_name=$(uci show dhcp 2>/dev/null | grep '=dnsmasq$' | head -n1 | cut -d'.' -f2 | cut -d'=' -f1)

if [ -z "$section_name" ]; then
    log "❌ 未找到 dnsmasq 配置段，请检查 dhcp 配置"
    exit 1
fi

# 检查当前 addnhosts 列表中是否已包含目标路径
already_exists=false
while IFS= read -r entry; do
    if [ "$entry" = "$HOSTS_FILE" ]; then
        already_exists=true
        break
    fi
done <<< "$(uci get dhcp."$section_name".addnhosts 2>/dev/null | tr ' ' '\n')"

if [ "$already_exists" = true ]; then
    log "ℹ️ addnhosts 路径已存在，跳过 uci 修改"
else
    uci add_list dhcp."$section_name".addnhosts="$HOSTS_FILE"
    uci commit dhcp
    log "✅ 已添加 addnhosts 路径: $HOSTS_FILE"
fi

# === 重启 dnsmasq 服务 ===
log "🔄 重启 dnsmasq 服务"
/etc/init.d/dnsmasq restart

# === 验证服务状态 ===
sleep 2
if /etc/init.d/dnsmasq status > /dev/null 2>&1; then
    log "✅ 更新成功，dnsmasq 运行正常"
else
    log "❌ dnsmasq 启动失败，请检查配置"
    exit 1
fi

log "🎉 多源 hosts 更新完成"
exit 0
