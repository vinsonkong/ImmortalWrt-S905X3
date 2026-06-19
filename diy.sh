#!/bin/bash

# 1. 修改默认 IP 地址 (改为 192.168.2.1，避免与主路由/光猫冲突)
sed -i 's/192.168.1.1/192.168.30.254/g' package/base-files/files/bin/config_generate

# 2. 修改默认主机名
sed -i 's/ImmortalWrt/X96Max/g' package/base-files/files/bin/config_generate

# 3. 设置默认时区为 Asia/Shanghai (北京时间)
sed -i "s/'UTC'/'CST-8'\n   set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

# 4. 替换默认主题为 Argon (ImmortalWrt 官方源自带)
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile





mkdir -p package/base-files/files/etc/uci-defaults

cat <<'SCRIPT_EOF' > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh

uci -q batch <<UCI_EOF

set network.lan.ipaddr='192.168.30.254'
set network.lan.gateway='192.168.30.1'
set network.lan.dns='223.5.5.5 8.8.8.8 114.114.114.114'

set network.lan6=interface
set network.lan6.proto='dhcpv6'
set network.lan6.device='@lan'
set network.lan6.reqaddress='try'
set network.lan6.reqprefix='auto'
set network.lan6.norelease='1'
set network.lan6.sourcefilter='0'
set network.lan6.delegate='0'
commit network

set dhcp.lan.ignore='1'
commit dhcp

set system.@system[0].hostname='x96max'
set system.@system[0].zonename='Asia/Shanghai'
set system.@system[0].timezone='CST-8'
commit system

add_list firewall.lan.network='lan6'
commit firewall

UCI_EOF

SCRIPT_EOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings




echo "DIY script execution completed!"


#!/bin/bash
# =========================================================
# diy.sh - Target 层白名单清理脚本
# 执行时机：Clone source code 之后，Update feeds 之前
# =========================================================

echo "🚀 开始执行 Target 层白名单清理，剔除 ImmortalWrt 默认全家桶..."

# 1. 定位 armvirt (S905X3 使用的通用架构) 的 Makefile
TARGET_MAKEFILE="target/linux/armvirt/Makefile"

if [ -f "$TARGET_MAKEFILE" ]; then
    # 2. 删除原有的 DEFAULT_PACKAGES 定义 (剔除官方强塞的冗余包，如各种无线驱动、多余 kmod 等)
    sed -i '/^DEFAULT_PACKAGES +=/d' "$TARGET_MAKEFILE"
    
    # 3. 重新写入我们的“基础白名单” (只保留系统启动、基础网络和 LuCI 核心必须的包)
    cat >> "$TARGET_MAKEFILE" <<EOF

# === 自定义基础白名单 (Custom Minimal Packages) ===
# 核心系统
DEFAULT_PACKAGES += base-files busybox dropbear opkg
# 基础网络与防火墙
DEFAULT_PACKAGES += dnsmasq-full firewall4 nftables kmod-nft-offload
# LuCI 核心基础
DEFAULT_PACKAGES += luci luci-base luci-compat luci-lib-ipkg
EOF
    
    echo "✅ Target 默认包已精简为极简白名单模式！"
else
    echo "⚠️ 未找到 $TARGET_MAKEFILE，跳过清理。"
fi

echo "🎉 DIY 脚本执行完毕！"

