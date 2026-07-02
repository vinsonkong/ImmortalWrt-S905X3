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

# =========================================================
# 辅助函数：尝试使用代理下载文件
# $1: 下载 URL
# $2: 输出文件路径
# =========================================================
download_with_proxy() {
    local url=$1
    local output=$2
    local proxy_url="https://ghproxy.com/${url}"
    
    echo "⬇️ 正在尝试下载: ${url}"
    # 首先尝试直接下载
    if wget -q --show-progress -O "$output" "$url"; then
        echo "✅ 下载成功"
        return 0
    else
        echo "⚠️ 直接下载失败，正在尝试代理加速: ${proxy_url}"
        # 如果直接下载失败，则尝试通过代理下载
        if wget -q --show-progress -O "$output" "$proxy_url"; then
            echo "✅ 代理下载成功"
            return 0
        else
            echo "❌ 所有下载源均失败: ${url}"
            return 1
        fi
    fi
}

# ================= [ 1. Navidrome 二进制文件下载 ] =================
echo "🎵 1. 注入 Navidrome 二进制文件..."
NAVIDROME_VERSION="0.62.0"
# 修改架构为 x86_64 (N5105 适配)
NAVIDROME_ARCH="amd64"

mkdir -p "${BASE_FILES}/usr/bin"
echo "⬇️ 正在下载 Navidrome ${NAVIDROME_VERSION} (${NAVIDROME_ARCH})..."
# 使用辅助函数进行下载
if download_with_proxy "https://github.com/navidrome/navidrome/releases/download/v${NAVIDROME_VERSION}/navidrome_${NAVIDROME_VERSION}_linux_${NAVIDROME_ARCH}.tar.gz" /tmp/navidrome.tar.gz; then
    tar -xzf /tmp/navidrome.tar.gz -C "${BASE_FILES}/usr/bin/" navidrome
    rm -f /tmp/navidrome.tar.gz
    chmod +x "${BASE_FILES}/usr/bin/navidrome"
    echo "✅ Navidrome 二进制已注入"
else
    exit 1
fi

# ================= [ 2. Lucky 大吉面板二进制下载 ] =================
echo "🍀 2. 注入 Lucky 大吉面板二进制..."
LUCKY_VERSION="2.27.世上"
# 修改架构为 x86_64 (N5105 适配)
LUCKY_ARCH="amd64"

# 定义下载源：优先万吉版直链，备选 GitHub 轻量版
WANJI_URL="https://release.66666.host/v${LUCKY_VERSION}/${LUCKY_VERSION}_wanji/lucky_${LUCKY_VERSION}_Linux_${LUCKY_ARCH}_wanji.tar.gz"
GITHUB_URL="https://github.com/gdy666/lucky/releases/download/v${LUCKY_VERSION}/lucky_${LUCKY_VERSION}_linux_${LUCKY_ARCH}.tar.gz"

mkdir -p "${BASE_FILES}/usr/bin"
rm -f /tmp/lucky.tar.gz

echo "⬇️ 正在尝试下载 Lucky 万吉版 v${LUCKY_VERSION} (${LUCKY_ARCH})..."
# 优先尝试万吉版
if download_with_proxy "$WANJI_URL" /tmp/lucky.tar.gz; then
    echo "✅ 万吉版下载成功"
elif download_with_proxy "$GITHUB_URL" /tmp/lucky.tar.gz; then
    # 万吉版失败后回退到 GitHub
    echo "⚠️ 万吉版下载失败，已回退至 GitHub 轻量版"
else
    echo "❌ 所有 Lucky 下载源均失败，请检查网络或版本号"
    exit 1
fi

# 校验文件是否为有效的 tar.gz 压缩包（防止下载到 HTML 错误页）
if ! tar -tzf /tmp/lucky.tar.gz > /dev/null 2>&1; then
    echo "❌ 下载的 Lucky 文件不是有效的 tar.gz 格式，可能为错误页面"
    rm -f /tmp/lucky.tar.gz
    exit 1
fi

tar -xzf /tmp/lucky.tar.gz -C "${BASE_FILES}/usr/bin/" lucky
rm -f /tmp/lucky.tar.gz
chmod +x "${BASE_FILES}/usr/bin/lucky"
echo "✅ Lucky 二进制已注入 ${BASE_FILES}/usr/bin/lucky"


# ========== EasyTier 二进制下载集成 ==========
EASYTIER_VERSION="v2.6.4"  # 保持 v 前缀
# 修改架构为 x86_64 (N5105 适配)
TARGET_ARCH="amd64"

echo ">>> 开始下载 EasyTier ${EASYTIER_VERSION} (${TARGET_ARCH})..."

# 1. 构建下载链接
DOWNLOAD_URL="https://github.com/EasyTier/EasyTier/releases/download/${EASYTIER_VERSION}/easytier-linux-${TARGET_ARCH}-${EASYTIER_VERSION}.zip"

# 2. 创建临时目录
mkdir -p /tmp/easytier-dl

# 3. 下载逻辑（带重试和镜像）
# 使用辅助函数进行下载
if download_with_proxy "$DOWNLOAD_URL" /tmp/easytier-dl/easytier.zip; then
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
        echo ">>> ✅ EasyTier 安装完成"
    else
        echo "❌ 下载的文件不是有效的 ZIP 格式"
        rm -rf /tmp/easytier-dl
        exit 1
    fi
else
    echo "❌ EasyTier 下载失败"
    rm -rf /tmp/easytier-dl
    exit 1
fi

echo "🎉 diyX86.sh 全部执行完毕！"
