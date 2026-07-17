#!/bin/sh
# ============================================================
# OpenWrt Docker 后台批量拉取脚本
# 用法: ./docker-pull-bg.sh [镜像列表文件] [--silent]
# 示例: ./docker-pull-bg.sh /tmp/images.txt --silent
#       ./docker-pull-bg.sh  (默认读取同目录下 images.txt)
# ============================================================

# ---------- 后台执行入口 (内部调用，用户无需感知) ----------
if [ "${_DOCKER_PULL_BG_EXEC}" = "1" ]; then
    TOTAL=0; SUCCESS=0; FAIL=0
    START_TIME=$(date +%s)
    
    while IFS= read -r img || [ -n "$img" ]; do
        # 去除注释和首尾空白
        img=$(echo "$img" | sed 's/#.*//' | xargs)
        [ -z "$img" ] && continue
        
        TOTAL=$((TOTAL + 1))
        echo "[$(date '+%H:%M:%S')] [$TOTAL] Pulling: $img"
        
        if docker pull "$img" >/dev/null 2>&1; then
            SUCCESS=$((SUCCESS + 1))
            echo "  ✅ Success"
        else
            FAIL=$((FAIL + 1))
            echo "  ❌ Failed"
        fi
    done < "$IMAGES_FILE"
    
    END_TIME=$(date +%s)
    COST=$((END_TIME - START_TIME))
    echo ""
    echo "========== 拉取完成 =========="
    echo "总计: $TOTAL | 成功: $SUCCESS | 失败: $FAIL | 耗时: ${COST}s"
    exit 0
fi

# ---------- 主逻辑 ----------
IMAGES_FILE="${1:-$(dirname "$0")/images.txt}"
SILENT=0
LOG_FILE="/tmp/docker-pull-$(date +%Y%m%d-%H%M%S).log"

for arg in "$@"; do
    case "$arg" in
        --silent) SILENT=1 ;;
    esac
done

# 前置检查
if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] docker 未安装" >&2; exit 1
fi

if [ ! -f "$IMAGES_FILE" ]; then
    echo "[ERROR] 镜像列表文件不存在: $IMAGES_FILE" >&2
    echo "请创建文件并每行写入一个镜像名，例如:" >&2
    echo "  nginx:alpine" >&2
    echo "  redis:7" >&2
    exit 1
fi

# OpenWrt Flash 安全检查
ROOT_DIR=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
case "$ROOT_DIR" in
    /overlay*|/rom*) 
        echo "[WARN] Docker 存储在 Flash ($ROOT_DIR)，强烈建议迁移到外接存储！" >&2 ;;
esac

# ---------- 执行分发 ----------
if [ "$SILENT" -eq 1 ]; then
    export _DOCKER_PULL_BG_EXEC=1
    export IMAGES_FILE
    
    nohup sh "$0" > "$LOG_FILE" 2>&1 &
    PID=$!
    
    echo "✅ 后台拉取已启动 (PID: $PID)"
    echo "📋 日志文件: $LOG_FILE"
    echo "🔍 查看进度: tail -f $LOG_FILE"
else
    pull_images_fg() {
        TOTAL=0; SUCCESS=0; FAIL=0
        START_TIME=$(date +%s)
        while IFS= read -r img || [ -n "$img" ]; do
            img=$(echo "$img" | sed 's/#.*//' | xargs)
            [ -z "$img" ] && continue
            TOTAL=$((TOTAL + 1))
            echo "[$(date '+%H:%M:%S')] [$TOTAL] Pulling: $img"
            if docker pull "$img" >/dev/null 2>&1; then
                SUCCESS=$((SUCCESS + 1)); echo "  ✅ Success"
            else
                FAIL=$((FAIL + 1)); echo "  ❌ Failed"
            fi
        done < "$IMAGES_FILE"
        END_TIME=$(date +%s)
        COST=$((END_TIME - START_TIME))
        echo ""; echo "========== 拉取完成 =========="
        echo "总计: $TOTAL | 成功: $SUCCESS | 失败: $FAIL | 耗时: ${COST}s"
    }
    
    pull_images_fg 2>&1 | while IFS= read -r line; do
        printf '%s\n' "$line"
        printf '%s\n' "$line" >> "$LOG_FILE"
    done
fi
