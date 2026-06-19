#!/bin/bash
# =========================================================
# diy.sh - 综合自定义脚本 (Target清理 + 基础配置注入)
# 执行时机：必须在 Update & Install feeds 之后执行！
# 适配架构：armvirt/64 (用于 ophub 打包 S905X3)
# =========================================================

echo "🚀 1. 开始执行 Target 层白名单清理..."
# ⭐ 修正：armvirt 的定义文件是 target.mk 而非 Makefile
TARGET_MK="target/linux/armvirt/target.mk"
if [ -f "$TARGET_MK" ]; then
    # 剔除官方强塞的冗余包
    sed -i '/^DEFAULT_PACKAGES +=/d' "$TARGET_MK"
    
    # 写入极简白名单 (包含 armvirt 核心驱动 + Argon 主题)
    cat >> "$TARGET_MK" <<EOF

# === 自定义基础白名单 (armvirt/64) ===
DEFAULT_PACKAGES += base-files busybox dropbear opkg
DEFAULT_PACKAGES += dnsmasq-full firewall4 nftables kmod-nft-offload
DEFAULT_PACKAGES += luci luci-base luci-compat luci-lib-ipkg
DEFAULT_PACKAGES += luci-theme-argon luci-app-argon-config
# ⭐ armvirt 核心依赖：确保 Ophub 打包时 rootfs 包含必要的虚拟设备驱动
DEFAULT_PACKAGES += kmod-virtio-net kmod-virtio-blk kmod-virtio-scsi
EOF
    echo "✅ Target 默认包已精简！"
else
    echo "⚠️ 未找到 $TARGET_MK，跳过 Target 白名单清理。"
fi

echo "🎨 2. 开始注入自定义基础配置..."

# 1. 修改默认 IP 地址 (改为 192.168.30.254，旁路由常用 IP)
sed -i 's/192.168.1.1/192.168.30.254/g' package/base-files/files/bin/config_generate

# 2. 修改默认主机名
sed -i 's/ImmortalWrt/X96Max/g' package/base-files/files/bin/config_generate

# 3. 设置默认时区为 Asia/Shanghai (北京时间)
sed -i "s/'UTC'/'CST-8'\n   set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

# ⭐ 已移除：替换默认主题为 Argon 的 sed 操作
# 原因：.config 中已通过 CONFIG_PACKAGE_luci-theme-argon=y 显式启用，
#       且 CONFIG_PACKAGE_luci-theme-bootstrap is not set 已禁用 Bootstrap，
#       make defconfig 会自动处理主题优先级，无需手动修改 feeds Makefile。

# 4. 注入 UCI 默认配置 (旁路由模式：关 DHCP、设网关 DNS、IPv6 穿透)
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
