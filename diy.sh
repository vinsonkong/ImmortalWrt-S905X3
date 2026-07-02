#!/bin/bash
set -e

# =========================================================
# 环境自适应检测 (兼容 ImageBuilder 与源码编译)
# =========================================================
if [ -d "package/base-files/files" ]; then
    echo "🔍 检测到【源码编译】环境"
    BASE_FILES="package/base-files/files"
    IS_IMAGEBUILDER=false
elif [ -f ".config" ] || [ -d "files" ]; then
    echo "🔍 检测到【ImageBuilder】环境"
    BASE_FILES="files"
    IS_IMAGEBUILDER=true
else
    echo "❌ 无法识别编译环境，退出"; exit 1
fi

# ================= [ 1. Navidrome 二进制文件下载 ] =================
echo "🎵 1. 注入 Navidrome 二进制文件..."
NAVIDROME_VERSION="0.62.0"
NAVIDROME_ARCH="arm64"

mkdir -p "${BASE_FILES}/usr/bin"
echo "⬇️ 正在下载 Navidrome ${NAVIDROME_VERSION} (${NAVIDROME_ARCH})..."
wget -q "https://github.com/navidrome/navidrome/releases/download/v${NAVIDROME_VERSION}/navidrome_${NAVIDROME_VERSION}_linux_${NAVIDROME_ARCH}.tar.gz" -O /tmp/navidrome.tar.gz
tar -xzf /tmp/navidrome.tar.gz -C "${BASE_FILES}/usr/bin/" navidrome
rm -f /tmp/navidrome.tar.gz
chmod +x "${BASE_FILES}/usr/bin/navidrome"
echo "✅ Navidrome 二进制已注入"

# ================= [ 2. Lucky 大吉面板二进制下载 ] =================
echo "🍀 2. 注入 Lucky 大吉面板二进制..."
LUCKY_VERSION="2.27.2"
LUCKY_ARCH="arm64"

echo "⬇️ 正在下载 Lucky v${LUCKY_VERSION} (${LUCKY_ARCH})..."
wget -q "https://github.com/gdy666/lucky/releases/download/v${LUCKY_VERSION}/lucky_${LUCKY_VERSION}_linux_${LUCKY_ARCH}.tar.gz" -O /tmp/lucky.tar.gz
tar -xzf /tmp/lucky.tar.gz -C "${BASE_FILES}/usr/bin/" lucky
rm -f /tmp/lucky.tar.gz
chmod +x "${BASE_FILES}/usr/bin/lucky"
echo "✅ Lucky 二进制已注入 /usr/bin/lucky"

# ========== EasyTier 二进制下载集成 ==========
EASYTIER_VERSION="v2.6.4"  # 保持 v 前缀
TARGET_ARCH="aarch64"       # 根据设备修改

echo ">>> 开始下载 EasyTier ${EASYTIER_VERSION} (${TARGET_ARCH})..."

# 1. 构建下载链接
DOWNLOAD_URL="https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/easytier-linux-${TARGET_ARCH}-${EASYTIER_VERSION}.zip"

# 2. 创建临时目录
mkdir -p /tmp/easytier-dl

# 3. 下载逻辑（带重试和镜像）
echo "⬇️ 正在下载: ${DOWNLOAD_URL}"
if wget -q --show-progress -O /tmp/easytier-dl/easytier.zip "$DOWNLOAD_URL"; then
    echo "✅ 下载成功"
else
    echo "⚠️ 官方下载失败，正在尝试镜像..."
    # 使用 ghproxy.com 加速（国内常用）
    MIRROR_URL="https://ghproxy.com/https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/easytier-linux-${TARGET_ARCH}-${EASYTIER_VERSION}.zip"
    if wget -q --show-progress -O /tmp/easytier-dl/easytier.zip "$MIRROR_URL"; then
        echo "✅ 镜像下载成功"
    else
        echo "❌ 所有源均下载失败，请检查网络"
        rm -rf /tmp/easytier-dl
        exit 1
    fi
fi

# 4. 解压与安装
if unzip -l /tmp/easytier-dl/easytier.zip > /dev/null 2>&1; then
    unzip -o /tmp/easytier-dl/easytier.zip -d /tmp/easytier-dl/
    
    # 查找文件（文件名通常包含架构后缀）
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

    # 清理
    rm -rf /tmp/easytier-dl
else
    echo "❌ 下载的文件不是有效的 ZIP 格式"
    rm -rf /tmp/easytier-dl
    exit 1
fi




echo "🎉 diy.sh 全部执行完毕！"
