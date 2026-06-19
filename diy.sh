#!/bin/bash
# =========================================================
# diy.sh - 综合自定义脚本 (Target清理 + 基础配置注入)
# 执行时机：必须在 Update & Install feeds 之后执行！
# =========================================================

echo "🚀 1. 开始执行 Target 层白名单清理..."
TARGET_MAKEFILE="target/linux/armvirt/Makefile"
if [ -f "$TARGET_MAKEFILE" ]; then
    # 剔除官方强塞的冗余包
    sed -i '/^DEFAULT_PACKAGES +=/d' "$TARGET_MAKEFILE"
    
    # 写入极简白名单 (包含 Argon 主题)
    cat >> "$TARGET_MAKEFILE" <<EOF

# === 自定义基础白名单 ===
DEFAULT_PACKAGES += base-files busybox dropbear opkg
DEFAULT_PACKAGES += dnsmasq-full firewall4 nftables kmod-nft-offload
DEFAULT_PACKAGES += luci luci-base luci-compat luci-lib-ipkg
DEFAULT_PACKAGES += luci-theme-argon luci-app-argon-config
EOF
    echo "✅ Target 默认包已精简！"
fi

echo "🎨 2. 开始注入自定义基础配置..."

# 1. 修改默认 IP 地址 (改为 192.168.30.254，旁路由常用 IP)
sed -i 's/192.168.1.1/192.168.30.254/g' package/base-files/files/bin/config_generate

# 2. 修改默认主机名
sed -i 's/ImmortalWrt/X96Max/g' package/base-files/files/bin/config_generate

# 3. 设置默认时区为 Asia/Shanghai (北京时间)
sed -i "s/'UTC'/'CST-8'\n   set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

# 4. 替换默认主题为 Argon (防止 feeds 中没有 bootstrap 导致 sed 报错，加了 2>/dev/null)
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true

# 5. 注入 UCI 默认配置 (旁路由模式：关 DHCP、设网关 DNS、IPv6 穿透)
echo "🔧 3. 注入 99-custom-settings (旁路由 UCI 配置)..."
mkdir -p package/base-files/files/etc/uci-defaults

cat <<'SCRIPT_EOF' > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh

uci -q batch <<UCI_EOF
# 网络配置 (旁路由核心)
set network.lan.ipaddr='192.168.30.254'
set network.lan.gateway='192.168.30.1'
set network.lan.dns='223.5.5.5 8.8.8.8 114.114.114.114'

# IPv6 穿透配置
set network.lan6=interface
set network.lan6.proto='dhcpv6'
set network.lan6.device='@lan'
set network.lan6.reqaddress='try'
set network.lan6.reqprefix='auto'
set network.lan6.norelease='1'
set network.lan6.sourcefilter='0'
set network.lan6.delegate='0'
commit network

# 关闭 DHCP (旁路由必须关闭)
set dhcp.lan.ignore='1'
commit dhcp

# 系统与主题配置
set system.@system[0].hostname='X96Max'
set system.@system[0].zonename='Asia/Shanghai'
set system.@system[0].timezone='CST-8'
commit system

# 防火墙配置 (允许 IPv6 穿透)
add_list firewall.lan.network='lan6'
commit firewall
UCI_EOF
SCRIPT_EOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

echo "🎉 DIY 脚本全部执行完毕！"
