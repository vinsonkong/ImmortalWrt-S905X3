#!/bin/bash
# =========================================================
# diy.sh - 综合自定义脚本 (Target清理 + 基础配置注入)
# 执行时机：必须在 Update & Install feeds 之后执行！
# 适配架构：armvirt/64 (用于 ophub 打包 S905X3)
# =========================================================

echo "🚀 1. 开始执行 Target 层白名单清理..."
TARGET_FILE=""

# 兼容 24.10 的 armsr 和旧版的 armvirt
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
    sed -i '/^DEFAULT_PACKAGES +=/d' "$TARGET_FILE"
    cat >> "$TARGET_FILE" <<EOF
# === 自定义基础白名单 ===
DEFAULT_PACKAGES += base-files busybox dropbear opkg
DEFAULT_PACKAGES += dnsmasq-full firewall4 nftables kmod-nft-offload
DEFAULT_PACKAGES += luci luci-base luci-compat luci-lib-ipkg
DEFAULT_PACKAGES += luci-theme-argon luci-app-argon-config
DEFAULT_PACKAGES += kmod-virtio-net kmod-virtio-blk kmod-virtio-scsi
EOF
    echo "✅ Target 默认包已精简！(文件: $TARGET_FILE)"
else
    echo "ℹ️ 未找到 Target 定义文件，已由 .config 全权管理，跳过白名单清理。"
fi


echo "🎨 2. 开始注入自定义基础配置..."

# 1. 修改默认 IP 地址 (改为 192.168.30.254，旁路由常用 IP)
sed -i 's/192.168.1.1/192.168.30.254/g' package/base-files/files/bin/config_generate

# 2. 修改默认主机名
sed -i 's/ImmortalWrt/X96Max/g' package/base-files/files/bin/config_generate

# 3. 设置默认时区为 Asia/Shanghai (北京时间)
sed -i "s/'UTC'/'CST-8'\n   set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

# 4. 注入 UCI 默认配置 (旁路由模式：关 DHCP、设网关 DNS、IPv6 穿透)
echo "🔧 3. 注入 99-custom-settings (旁路由 UCI 配置)..."
mkdir -p package/base-files/files/etc/uci-defaults

cat <<'SCRIPT_EOF' > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh

uci -q batch <<UCI_EOF
# 网络配置 (旁路由核心)
set network.lan.ipaddr='192.168.30.254'
set network.lan.gateway='192.168.30.1'
# 使用 list 语法确保多 DNS 兼容性
delete network.lan.dns
add_list network.lan.dns='223.5.5.5'
add_list network.lan.dns='8.8.8.8'
add_list network.lan.dns='114.114.114.114'

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

# 防火墙配置 (允许 IPv6 穿透，兼容不同 ImmortalWrt 版本)
# 先尝试将 lan6 加入 lan zone，若失败则创建独立 zone
uci -q get firewall.lan >/dev/null && {
    add_list firewall.lan.network='lan6'
} || {
    set firewall.lan6=zone
    set firewall.lan6.name='lan6'
    set firewall.lan6.network='lan6'
    set firewall.lan6.input='ACCEPT'
    set firewall.lan6.output='ACCEPT'
    set firewall.lan6.forward='ACCEPT'
}
commit firewall
UCI_EOF
SCRIPT_EOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

echo "🎉 DIY 脚本全部执行完毕！"
