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

# echo "🍀 2. 注入 Lucky 大吉面板二进制..."
# LUCKY_VERSION="2.27.2"
# LUCKY_ARCH="arm64"

# echo "⬇️ 正在下载 Lucky v${LUCKY_VERSION} (${LUCKY_ARCH})..."
# wget -q "https://github.com/gdy666/lucky/releases/download/v${LUCKY_VERSION}/lucky_${LUCKY_VERSION}_linux_${LUCKY_ARCH}.tar.gz" -O /tmp/lucky.tar.gz
# tar -xzf /tmp/lucky.tar.gz -C "${BASE_FILES}/usr/bin/" lucky
# rm -f /tmp/lucky.tar.gz
# chmod +x "${BASE_FILES}/usr/bin/lucky"
# echo "✅ Lucky 二进制已注入 /usr/bin/lucky"


# ================= [ 3. 防御性优化：CRLF清理与uhttpd证书占位 ] =================
echo "🛡️ 3. 执行防御性优化 (防编译 EOF 错误)..."

# 3.1 强制清理所有注入文件的 CRLF 换行符
find "${BASE_FILES}" -type f -exec sed -i 's/\r$//' {} + 2>/dev/null || true
echo "✅ 已清理所有注入文件的 CRLF 换行符"

# 3.2 创建非空 uhttpd 证书占位文件 (骗过 postinst 检查，跳过自动生成)
UHTTPD_CERT="${BASE_FILES}/etc/uhttpd.crt"
UHTTPD_KEY="${BASE_FILES}/etc/uhttpd.key"
mkdir -p "${BASE_FILES}/etc"
echo "dummy cert" > "$UHTTPD_CERT"
echo "dummy key" > "$UHTTPD_KEY"
echo "✅ 已创建 uhttpd 证书占位文件"

echo "🎉 diy.sh 全部执行完毕！"
