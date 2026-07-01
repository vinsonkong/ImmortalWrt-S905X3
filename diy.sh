#!/bin/bash
set -e

# =========================================================
# 环境自适应检测 (核心：兼容 ImageBuilder 与 源码编译)
# =========================================================
if [ -d "package/base-files/files" ]; then
    echo "🔍 检测到【源码编译】环境"
    BASE_FILES="package/base-files/files"
    TARGET_DIR="target/linux"
    IS_IMAGEBUILDER=false
elif [ -f ".config" ] || [ -d "files" ]; then
    echo "🔍 检测到【ImageBuilder】环境"
    BASE_FILES="files"
    TARGET_DIR=""
    IS_IMAGEBUILDER=true
else
    echo "❌ 无法识别编译环境，退出"; exit 1
fi

# ================= [ 0. 终极修复：清理 CRLF 换行符 ] =================
# 🚨 核心修复：必须在 workflow 复制 custom-files 之前，清理其 CRLF！
# 否则 uci 读取 hostname 时会带入 \r，导致 uhttpd 生成证书时 openssl 命令引号不匹配！
echo "🧹 0. 强制清理 CRLF 换行符 (修复 uhttpd 证书生成 EOF 错误)..."

# 清理 ../custom-files 目录 (位于 openwrt 的上一级)
if [ -d "../custom-files" ]; then
    find "../custom-files" -type f -exec file {} + 2>/dev/null | grep -i "text" | cut -d: -f1 | xargs -r sed -i 's/\r$//' 2>/dev/null || true
    find "../custom-files" -type f -name "*.sh" -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    find "../custom-files/etc" -type f -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    echo "✅ 已清理 ../custom-files 中的 CRLF"
fi

# 清理当前 BASE_FILES 目录
if [ -d "${BASE_FILES}" ]; then
    find "${BASE_FILES}" -type f -exec sed -i 's/\r$//' {} + 2>/dev/null || true
fi

# ================= [ 1. Target 层白名单清理 ] =================
echo "🚀 1. Target 层白名单清理..."
if [ "$IS_IMAGEBUILDER" = false ] && [ -n "$TARGET_DIR" ]; then
    TARGET_FILE=""
    if [ -f "${TARGET_DIR}/armsr/armv8/target.mk" ]; then
        TARGET_FILE="${TARGET_DIR}/armsr/armv8/target.mk"
    elif [ -f "${TARGET_DIR}/armsr/target.mk" ]; then
        TARGET_FILE="${TARGET_DIR}/armsr/target.mk"
    elif [ -f "${TARGET_DIR}/armvirt/target.mk" ]; then
        TARGET_FILE="${TARGET_DIR}/armvirt/target.mk"
    elif [ -f "${TARGET_DIR}/armvirt/Makefile" ]; then
        TARGET_FILE="${TARGET_DIR}/armvirt/Makefile"
    fi

    if [ -n "$TARGET_FILE" ]; then
        cp "$TARGET_FILE" "${TARGET_FILE}.bak"
        sed -i '/^DEFAULT_PACKAGES +=/d' "$TARGET_FILE"
        cat >> "$TARGET_FILE" <<EOF

# === 自定义基础白名单 (旁路由精简版) ===
DEFAULT_PACKAGES += base-files busybox dropbear opkg
DEFAULT_PACKAGES += dnsmasq-full firewall4 nftables kmod-nft-offload
DEFAULT_PACKAGES += luci luci-base luci-compat luci-lib-ipkg
DEFAULT_PACKAGES += luci-theme-argon
DEFAULT_PACKAGES += kmod-virtio-net kmod-virtio-blk kmod-virtio-scsi
EOF
        echo "✅ Target 默认包已精简并注入！(文件: $TARGET_FILE)"
    else
        echo "ℹ️ 未找到 Target 定义文件，跳过白名单清理。"
    fi
else
    echo "ℹ️ ImageBuilder 环境无 Target 目录，跳过白名单清理（由 PACKAGES 参数管理）。"
fi

# ================= [ 2. 修改 config_generate ] =================
echo "🎨 2. 修改 config_generate (Fallback 兜底)..."
CONFIG_GENERATE="${BASE_FILES}/bin/config_generate"
if [ -f "$CONFIG_GENERATE" ]; then
    # 确保 config_generate 本身也没有 CRLF
    sed -i 's/\r$//' "$CONFIG_GENERATE"
    
    sed -i 's/192.168.1.1/192.168.30.254/g' "$CONFIG_GENERATE"
    sed -i 's/ImmortalWrt/X96Max/g' "$CONFIG_GENERATE"
    
    if grep -q "'UTC'" "$CONFIG_GENERATE"; then
        sed -i "s/'UTC'/'CST-8'\n   set system.@system[-1].zonename='Asia\/Shanghai'/g" "$CONFIG_GENERATE"
        echo "✅ config_generate 已修改（IP/主机名/时区）"
    else
        echo "⚠️ config_generate 中未找到 'UTC' 字段，时区注入跳过"
    fi
else
    echo "⚠️ 未找到 config_generate，跳过（ImageBuilder 正常现象）"
fi

# ================= [ 3. Navidrome 二进制文件下载 ] =================
echo "🎵 3. 注入 Navidrome 二进制文件..."
NAVIDROME_VERSION="0.59.0"
NAVIDROME_ARCH="arm64"

mkdir -p "${BASE_FILES}/usr/bin"
echo "⬇️ 正在下载 Navidrome ${NAVIDROME_VERSION} (${NAVIDROME_ARCH})..."
wget -q "https://github.com/navidrome/navidrome/releases/download/v${NAVIDROME_VERSION}/navidrome_${NAVIDROME_VERSION}_linux_${NAVIDROME_ARCH}.tar.gz" -O /tmp/navidrome.tar.gz
tar -xzf /tmp/navidrome.tar.gz -C "${BASE_FILES}/usr/bin/" navidrome
rm -f /tmp/navidrome.tar.gz
chmod +x "${BASE_FILES}/usr/bin/navidrome"
echo "✅ Navidrome 二进制已注入至 ${BASE_FILES}/usr/bin/navidrome"

# ================= [ 4. uhttpd 证书生成兜底 ] =================
echo "🔧 4. 创建 uhttpd 证书占位文件 (双重保险)..."
UHTTPD_CERT="${BASE_FILES}/etc/uhttpd.crt"
UHTTPD_KEY="${BASE_FILES}/etc/uhttpd.key"
mkdir -p "${BASE_FILES}/etc"
# 写入非空内容，骗过 uhttpd 的 [ -s ] 检查，彻底跳过 postinst 自动生成
echo "dummy cert" > "$UHTTPD_CERT"
echo "dummy key" > "$UHTTPD_KEY"
echo "✅ 已创建非空 uhttpd 证书占位文件"

echo "🎉 diy.sh 执行完毕！"
