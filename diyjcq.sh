#!/bin/bash
set -e

# =========================================================
# 环境自适应检测 (仅用于确定文件注入路径)
# =========================================================
if [ -d "package/base-files/files" ]; then
    echo "🔍 检测到【源码编译】环境"
    BASE_FILES="package/base-files/files"
elif [ -f ".config" ] || [ -d "files" ]; then
    echo "🔍 检测到【ImageBuilder】环境"
    BASE_FILES="files"
else
    echo "❌ 无法识别编译环境，退出"; exit 1
fi


# ========== [ EasyTier 二进制下载集成 ] ==========
EASYTIER_VERSION="v2.6.3"
TARGET_ARCH="aarch64"

echo ">>> 开始下载 EasyTier ${EASYTIER_VERSION} (${TARGET_ARCH})..."
DOWNLOAD_URL="https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/easytier-linux-${TARGET_ARCH}-${EASYTIER_VERSION}.zip"

mkdir -p /tmp/easytier-dl

echo "⬇️ 正在下载: ${DOWNLOAD_URL}"
if wget -q --show-progress -O /tmp/easytier-dl/easytier.zip "$DOWNLOAD_URL"; then
    echo "✅ 下载成功"
else
    echo "⚠️ 官方下载失败，正在尝试镜像..."
    MIRROR_URL="https://ghproxy.com/https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/easytier-linux-${TARGET_ARCH}-${EASYTIER_VERSION}.zip"
    if wget -q --show-progress -O /tmp/easytier-dl/easytier.zip "$MIRROR_URL"; then
        echo "✅ 镜像下载成功"
    else
        echo "❌ 所有源均下载失败，请检查网络"
        rm -rf /tmp/easytier-dl
        exit 1
    fi
fi

if unzip -l /tmp/easytier-dl/easytier.zip > /dev/null 2>&1; then
    unzip -o /tmp/easytier-dl/easytier.zip -d /tmp/easytier-dl/
    
    CORE_BIN=$(find /tmp/easytier-dl -name "easytier-core*" -type f | head -n1)
    CLI_BIN=$(find /tmp/easytier-dl -name "easytier-cli*" -type f | head -n1)
    
    if [ -n "$CORE_BIN" ]; then
        mkdir -p "${BASE_FILES}/usr/bin"
        cp -f "$CORE_BIN" "${BASE_FILES}/usr/bin/easytier-core"
        chmod +x "${BASE_FILES}/usr/bin/easytier-core"
        echo ">>> ✅ easytier-core 已安装"
    else
        echo "❌ 未找到 easytier-core 文件，请检查压缩包结构"
        exit 1
    fi

    if [ -n "$CLI_BIN" ]; then
        cp -f "$CLI_BIN" "${BASE_FILES}/usr/bin/easytier-cli"
        chmod +x "${BASE_FILES}/usr/bin/easytier-cli"
        echo ">>> ✅ easytier-cli 已安装"
    fi

    rm -rf /tmp/easytier-dl
else
    echo "❌ 下载的文件不是有效的 ZIP 格式"
    rm -rf /tmp/easytier-dl
    exit 1
fi

echo "🎉 diyjcq.sh 全部执行完毕！"
exit 0
