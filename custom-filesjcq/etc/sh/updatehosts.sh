#!/bin/bash
# === 配置区 ===
HOSTS_FILE="/etc/hosts-new/hosts.combined"
LOG_FILE="/var/log/hosts-update.log"  # OpenWrt下为tmpfs，需持久化请改/root/
LOCK_FILE="/tmp/hosts-update.lock"

# 多源hosts列表（按国内访问友好度排序）
HOSTS_SOURCES=(
    "https://api.1doc.top/github/github-hosts.txt"
    "https://githubhosts.linkedbus.com"
    "https://hosts.gitcdn.top/hosts.txt"
    "https://raw.hellogithub.com/hosts"
    "https://raw.githubusercontent.com/maxiaof/github-hosts/master/hosts"
    "https://raw.githubusercontent.com/oopsunix/hosts/main/hosts_github"
)

# === 工具函数 ===
log() { echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE" | logger -t "hosts-update"; }
cleanup() { rm -f "$LOCK_FILE" "${TMP_FILES[@]}"; }
trap cleanup EXIT

# === 锁机制（含过期检测）===
if [ -f "$LOCK_FILE" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
    [ "$age" -gt 3600 ] && { log "⚠️ 过期锁文件(${age}s)，强制清除"; rm -f "$LOCK_FILE"; } || \
        { log "❌ 脚本运行中，跳过"; exit 1; }
fi
touch "$LOCK_FILE"

# === 前置校验 ===
[ -z "$HOSTS_FILE" ] && { echo "HOSTS_FILE未设置" >&2; exit 1; }
mkdir -p "$(dirname "$HOSTS_FILE")" || { log "❌ 目录创建失败"; exit 1; }

# === 下载+格式校验+合并 ===
MERGED_TMP=$(mktemp); TMP_FILES=("$MERGED_TMP")
success=0
for src in "${HOSTS_SOURCES[@]}"; do
    src_tmp=$(mktemp); TMP_FILES+=("$src_tmp")
    if curl -sL --connect-timeout 10 --max-time 30 --fail "$src" -o "$src_tmp" && \
       grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+[a-zA-Z]' "$src_tmp"; then
        cat "$src_tmp" >> "$MERGED_TMP"
        success=$((success + 1))
        log "✅ $src ($(wc -l < "$src_tmp")行)"
    else
        log "⚠️ 失败/格式无效: $src"
    fi
done

[ "$success" -eq 0 ] && { log "❌ 无有效源，终止"; exit 1; }

# 去重过滤并写入目标文件
awk 'NF && !/^#/ && !/^$/' "$MERGED_TMP" | sort -u > "$HOSTS_FILE"
[ ! -s "$HOSTS_FILE" ] && { log "❌ 合并结果为空"; exit 1; }
log "ℹ️ 合并完成: $(wc -l < "$HOSTS_FILE")条 (来自${success}个源)"

# === UCI配置（防重复）===
section=$(uci show dhcp 2>/dev/null | grep '=dnsmasq$' | head -1 | cut -d. -f2 | cut -d= -f1)
[ -z "$section" ] && { log "❌ 未找到dnsmasq配置"; exit 1; }

if ! uci get dhcp."$section".addnhosts 2>/dev/null | tr ' ' '\n' | grep -qx "$HOSTS_FILE"; then
    uci add_list dhcp."$section".addnhosts="$HOSTS_FILE"
    uci commit dhcp
    log "✅ 已添加addnhosts"
else
    log "ℹ️ addnhosts已存在"
fi

# === 重启并验证dnsmasq ===
/etc/init.d/dnsmasq restart
sleep 2
/etc/init.d/dnsmasq status &>/dev/null && log "✅ dnsmasq正常" || { log "❌ dnsmasq启动失败"; exit 1; }
log "🎉 更新完成"
