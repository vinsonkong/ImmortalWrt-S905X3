#!/bin/bash
# =========================================================
# diy.sh - 综合自定义脚本 (兼容 23.05 & 24.10)
# =========================================================

echo "🚀 1. 开始执行 Target 层白名单清理..."
TARGET_FILE=""

# 兼容 24.10 的 armsr 和 23.05 的 armvirt
if [ -f "target/linux/armsr/armv8/target.mk" ]; then
    TARGET_FILE="target/linux/armsr/armv8/target.mk"
elif [ -f "target/linux/armsr/target.mk" ]; then
    TARGET_FILE="target/linux/armsr/target.mk"
elif [ -f "target/linux/armvirt/target.mk" ]; then
    TARGET_FILE="target/linux/armvirt/target.mk"
elif [ -f "target/linux/armvirt/Makefile" ]; then
    TARGET_FILE="target/linux/armvirt/Makefile"
fi

if [ -n "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" "${TARGET_FILE}.bak"
    sed -i '/^DEFAULT_PACKAGES +=/d' "$TARGET_FILE"
    cat >> "$TARGET_FILE" <<EOF

# === 自定义基础白名单 (旁路由精简版) ===
DEFAULT_PACKAGES += base-files busybox dropbear opkg
DEFAULT_PACKAGES += dnsmasq-full firewall4 nftables kmod-nft-offload
DEFAULT_PACKAGES += luci luci-base luci-compat luci-lib-ipkg
DEFAULT_PACKAGES += luci-theme-argon luci-app-argon-config
DEFAULT_PACKAGES += kmod-virtio-net kmod-virtio-blk kmod-virtio-scsi
EOF
    echo "✅ Target 默认包已精简并注入！(文件: $TARGET_FILE)"
else
    echo "ℹ️ 未找到 Target 定义文件，已由 .config 全权管理，跳过白名单清理。"
fi


echo "🎨 2. 开始注入自定义基础配置..."

sed -i 's/192.168.1.1/192.168.30.254/g' package/base-files/files/bin/config_generate
sed -i 's/ImmortalWrt/X96Max/g' package/base-files/files/bin/config_generate
sed -i "s/'UTC'/'CST-8'\n   set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate


echo "🔧 3. 注入 99-custom-settings (旁路由 UCI 默认配置)..."
mkdir -p package/base-files/files/etc/uci-defaults

cat <<'SCRIPT_EOF' > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh
# =========================================================
# 旁路由初始化脚本 (兼容 23.05 ifname 与 24.10 device 模型)
# =========================================================

# --- 1. 网络配置 (旁路由核心) ---
uci -q set network.lan.proto='static'
uci -q set network.lan.ipaddr='192.168.30.254'
uci -q set network.lan.netmask='255.255.255.0'
uci -q set network.lan.gateway='192.168.30.1'

# 兼容处理：24.10 使用 device='br-lan'，23.05 可能使用 ifname='eth0'
uci -q set network.lan.device='br-lan'
uci -q set network.lan.ifname='eth0' 

# 清空原有 DNS 并添加公共 DNS
uci -q delete network.lan.dns
uci -q add_list network.lan.dns='223.5.5.5'
uci -q add_list network.lan.dns='114.114.114.114'
uci -q add_list network.lan.dns='8.8.8.8'

uci -q set network.lan.delegate='0'

# --- 2. IPv6 穿透配置 ---
uci -q delete network.lan6
uci -q set network.lan6=interface
uci -q set network.lan6.proto='dhcpv6'
# 兼容处理：lan6 绑定到 br-lan 或 eth0
uci -q set network.lan6.device='br-lan'
uci -q set network.lan6.reqaddress='try'
uci -q set network.lan6.reqprefix='auto'
uci -q set network.lan6.norelease='1'
uci -q set network.lan6.sourcefilter='0'
uci -q set network.lan6.delegate='0'
uci commit network

# --- 3. 关闭 DHCP 服务 ---
uci -q set dhcp.lan.ignore='1'
uci -q set dhcp.lan.dhcpv6='disabled'
uci -q set dhcp.lan.ra='disabled'
uci -q set dhcp.lan.ndp='disabled'
uci commit dhcp

# --- 4. 系统与主题配置 ---
uci -q set system.@system[0].hostname='X96Max'
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q set system.@system[0].timezone='CST-8'
uci commit system

# --- 5. 防火墙配置 (允许 IPv6 穿透) ---
ZONE_IDX=$(uci show firewall | grep -E "name='lan'$" | cut -d'.' -f2 | cut -d'=' -f1 | head -n 1)
if [ -n "$ZONE_IDX" ]; then
    uci -q delete firewall.${ZONE_IDX}.network
    uci add_list firewall.${ZONE_IDX}.network='lan'
    uci add_list firewall.${ZONE_IDX}.network='lan6'
    uci commit firewall
fi

# --- 6. 应用配置 ---
/etc/init.d/network restart
/etc/init.d/firewall restart

exit 0
SCRIPT_EOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

echo "🎉 DIY 脚本全部执行完毕！"
