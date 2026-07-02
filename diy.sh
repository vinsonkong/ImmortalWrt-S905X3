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
NAVIDROME_VERSION="0.59.0"
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

# ==========================================
# EasyTier 二进制下载集成
# ==========================================
EASYTIER_VERSION="v2.6.4"  # 可修改为指定版本，留空则自动获取最新版
TARGET_ARCH="arm64"       # 根据目标设备修改: x86_64 / aarch64 / armv7 / mipsel 等

echo ">>> 开始下载 EasyTier ${EASYTIER_VERSION} (${TARGET_ARCH})..."

# 1. 确定下载链接
if [ -z "$EASYTIER_VERSION" ]; then
    EASYTIER_VERSION=$(curl -s https://api.github.com/repos/EasyTier/EasyTier/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
fi
DOWNLOAD_URL="https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/easytier-linux-${TARGET_ARCH}-${EASYTIER_VERSION}.zip"

# 2. 创建临时目录并下载
mkdir -p /tmp/easytier-dl
wget -q --show-progress -O /tmp/easytier-dl/easytier.zip "$DOWNLOAD_URL" || {
    echo "!!! GitHub 下载失败，尝试使用镜像加速..."
    wget -q --show-progress -O /tmp/easytier-dl/easytier.zip "https://ghfast.top/$DOWNLOAD_URL"
}

# 3. 解压并安装到固件根文件系统
if [ -f /tmp/easytier-dl/easytier.zip ]; then
    unzip -o /tmp/easytier-dl/easytier.zip -d /tmp/easytier-dl/
    
    # 查找解压后的 easytier-core 二进制文件
    CORE_BIN=$(find /tmp/easytier-dl -name "easytier-core" -type f | head -n1)
    CLI_BIN=$(find /tmp/easytier-dl -name "easytier-cli" -type f | head -n1)
    
    if [ -n "$CORE_BIN" ]; then
        mkdir -p files/usr/bin
        cp -f "$CORE_BIN" files/usr/bin/easytier-core
        chmod +x files/usr/bin/easytier-core
        echo ">>> ✅ easytier-core 已安装到 files/usr/bin/"
    fi
    
    if [ -n "$CLI_BIN" ]; then
        cp -f "$CLI_BIN" files/usr/bin/easytier-cli
        chmod +x files/usr/bin/easytier-cli
        echo ">>> ✅ easytier-cli 已安装到 files/usr/bin/"
    fi
    
    # 清理临时文件
    rm -rf /tmp/easytier-dl
else
    echo "!!! ❌ EasyTier 下载失败，请检查网络或版本号"
fi


echo "🎉 diy.sh 全部执行完毕！"
