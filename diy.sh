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
    # 清理可能存在的 CRLF
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

# ================= [ 3. 静态注入所有 /etc/config 基础配置 ] =================
echo "🔧 3. 静态注入所有 /etc/config 基础配置..."
mkdir -p "${BASE_FILES}/etc/config"
mkdir -p "${BASE_FILES}/etc/dropbear"

# ================= [ 3.1 网络配置 ] =================
# ⚠️ 注意：UCI 配置文件必须使用 Tab 缩进，此处已严格使用 Tab 键
cat > "${BASE_FILES}/etc/config/network" <<'EOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'fddc:52f6:ea41::/48'
	option packet_steering '1'

config device
	option name 'br-lan'
	option type 'bridge'
	list ports 'eth0'

config interface 'lan'
	option device 'br-lan'
	option proto 'static'
	option ipaddr '192.168.30.254'
	option netmask '255.255.255.0'
	list dns '223.5.5.5'
	list dns '8.8.8.8'
	option gateway '192.168.30.1'

config interface 'lan6'
	option proto 'dhcpv6'
	option device '@lan'
	option reqaddress 'try'
	option reqprefix 'auto'
	option norelease '1'
	option sourcefilter '0'
	option delegate '0'

config interface 'docker'
	option device 'docker0'
	option proto 'none'
	option auto '0'

config device
	option type 'bridge'
	option name 'docker0'

config interface 'wwan'
	option proto 'dhcp'

config interface 'EasyTier'
	option proto 'none'
	option device 'easytier'
	option ifname 'easytier'
EOF

# ================= [ 3.2 DHCP 配置 ] =================
cat > "${BASE_FILES}/etc/config/dhcp" <<'EOF'
config dnsmasq
	option domainneeded '1'
	option localise_queries '1'
	option rebind_protection '1'
	option rebind_localhost '1'
	option local '/lan/'
	option domain 'lan'
	option expandhosts '1'
	option authoritative '1'
	option readethers '1'
	option leasefile '/tmp/dhcp.leases'
	option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
	option nonwildcard '1'
	option localservice '1'
	option ednspacket_max '1232'

config dhcp 'lan'
	option interface 'lan'
	option ignore '1'
	option dhcpv6 'disabled'
	option ra 'disabled'
	option ndp 'disabled'

config dhcp 'wan'
	option interface 'wan'
	option ignore '1'

config odhcpd 'odhcpd'
	option maindhcp '0'
	option leasefile '/tmp/hosts/odhcpd'
	option leasetrigger '/usr/sbin/odhcpd-update'
	option loglevel '4'
EOF

# ================= [ 3.3 Dropbear SSH 配置与公钥 ] =================
cat > "${BASE_FILES}/etc/config/dropbear" <<'EOF'
config dropbear
	option PasswordAuth 'on'
	option RootPasswordAuth 'on'
	option RootLogin '1'
	option Port '22'
EOF

cat > "${BASE_FILES}/etc/dropbear/authorized_keys" <<'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDg995BH9wmXnqi+voUaQT0oSYi+guKytDzJBMe0psHZDC1APuG5T1dfRdQzK2STWx3gq/b9cG8H9wm6KtSiQsTjQkvfVyuLSe4u9f0BChBEbUcfpvjt51Lnkobyo5Ppnj9l3v8TMehdVMcMluNciF8HxTJwrtuPiKcfLeqqUvzSU0wUdvkdq+rirusEhK45mzBZBmCDUq6fECxdEcKKCFmOUHM6CWdXJnAWk1ehchy+EGxMri5fG6uMJh4Y43vjVBYavN0aqW37ASkUe9LXuokYm0W2gBVzoZuCHBw09roPEeZvJYhSjdVrfmYXbi1qoyaHMjT0zSTSt6ov/WFfI+n x96max
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4un4qvoUbhkmaOvIEvRWZ5qlSrrqzRpUb8BsKn65bn x96max+
EOF

# 静态构建阶段：强制设置 Dropbear 目录及文件的权限
chmod 700 "${BASE_FILES}/etc/dropbear"
chmod 600 "${BASE_FILES}/etc/dropbear/authorized_keys"

# ================= [ 3.4 rc.local (动态逻辑) ] =================
cat > "${BASE_FILES}/etc/rc.local" <<'EOF'
#!/bin/sh
# 修复 Dropbear 文件夹及公钥的权限和归属 (防止 SSH 拒绝密钥登录)
chown -R root:root /etc/dropbear 2>/dev/null
chmod 700 /etc/dropbear 2>/dev/null
chmod 600 /etc/dropbear/authorized_keys 2>/dev/null

exit 0
EOF
chmod +x "${BASE_FILES}/etc/rc.local"
echo "✅ 所有基础配置已静态注入完毕！"

# ================= [ 4. Navidrome 二进制文件下载 ] =================
echo "🎵 4. 注入 Navidrome 二进制文件..."
NAVIDROME_VERSION="0.59.0"
# S905X3 / armsr armv8 均为 aarch64 架构
NAVIDROME_ARCH="arm64"

mkdir -p "${BASE_FILES}/usr/bin"
echo "⬇️ 正在下载 Navidrome ${NAVIDROME_VERSION} (${NAVIDROME_ARCH})..."
wget -q "https://github.com/navidrome/navidrome/releases/download/v${NAVIDROME_VERSION}/navidrome_${NAVIDROME_VERSION}_linux_${NAVIDROME_ARCH}.tar.gz" -O /tmp/navidrome.tar.gz
tar -xzf /tmp/navidrome.tar.gz -C "${BASE_FILES}/usr/bin/" navidrome
rm -f /tmp/navidrome.tar.gz
chmod +x "${BASE_FILES}/usr/bin/navidrome"

echo "✅ Navidrome 二进制及目录已注入"

# ================= [ 5. 防御性优化：CRLF清理与uhttpd证书占位 ] =================
echo "🛡️ 5. 执行防御性优化 (防编译 EOF 错误)..."

# 5.1 强制清理所有注入文件的 CRLF 换行符 (防止 uhttpd 证书生成引号不匹配)
find "${BASE_FILES}" -type f -exec sed -i 's/\r$//' {} + 2>/dev/null || true
echo "✅ 已清理所有注入文件的 CRLF 换行符"

# 5.2 创建非空 uhttpd 证书占位文件 (骗过 postinst 的 -s 检查，跳过自动生成)
UHTTPD_CERT="${BASE_FILES}/etc/uhttpd.crt"
UHTTPD_KEY="${BASE_FILES}/etc/uhttpd.key"
mkdir -p "${BASE_FILES}/etc"
echo "dummy cert" > "$UHTTPD_CERT"
echo "dummy key" > "$UHTTPD_KEY"
echo "✅ 已创建 uhttpd 证书占位文件"

echo "🎉 diy.sh 全部执行完毕！"
