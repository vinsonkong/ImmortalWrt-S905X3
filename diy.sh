#!/bin/bash
# =========================================================
# diy.sh - 综合自定义脚本 (Target清理 + 基础配置注入)
# 执行时机：必须在 Update & Install feeds 之后，make defconfig 之前执行！
# 适配架构：armsr/armv8 (ImmortalWrt 24.10+) / armvirt/64 (旧版)
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
    # 备份原文件
    cp "$TARGET_FILE" "${TARGET_FILE}.bak"
    # 删除原有的 DEFAULT_PACKAGES 定义
    sed -i '/^DEFAULT_PACKAGES +=/d' "$TARGET_FILE"
    # 注入自定义基础白名单
    cat >> "$TARGET_FILE" <<EOF

# === 自定义基础白名单 (旁路由精简版) ===
DEFAULT_PACKAGES += base-files busybox dropbear opkg
DEFAULT_PACKAGES += dnsmasq-full firewall4 nftables kmod-nft-offload
DEFAULT_PACKAGES += luci luci-base luci-compat luci-lib-ipkg
DEFAULT_PACKAGES += luci-theme-argon luci-app-argon-config
# ophub 打包及底层引导所需 virtio 驱动
DEFAULT_PACKAGES += kmod-virtio-net kmod-virtio-blk kmod-virtio-scsi
EOF
    echo "✅ Target 默认包已精简并注入！(文件: $TARGET_FILE)"
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


echo "🔧 3. 注入 99-custom-settings (旁路由 UCI 默认配置)..."
mkdir -p package/base-files/files/etc/uci-defaults

cat <<'SCRIPT_EOF' > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh
# =========================================================
# 旁路由初始化脚本 (首次启动时自动执行一次)
# 使用 uci -q 确保即使某项不存在也不会导致脚本中断
# =========================================================

# --- 1. 网络配置 (旁路由核心) ---
uci -q set network.lan.proto='static'
uci -q set network.lan.ipaddr='192.168.30.254'
uci -q set network.lan.netmask='255.255.255.0'
uci -q set network.lan.gateway='192.168.30.1'

# 清空原有 DNS 并添加公共 DNS
uci -q delete network.lan.dns
uci -q add_list network.lan.dns='223.5.5.5'
uci -q add_list network.lan.dns='114.114.114.114'
uci -q add_list network.lan.dns='8.8.8.8'

# 禁用 LAN 口的 DHCP 客户端行为
uci -q set network.lan.delegate='0'

# --- 2. IPv6 穿透配置 ---
# 删除旧的 lan6 防止冲突，重新创建
uci -q delete network.lan6
uci -q set network.lan6=interface
uci -q set network.lan6.proto='dhcpv6'
uci -q set network.lan6.device='@lan'
uci -q set network.lan6.reqaddress='try'
uci -q set network.lan6.reqprefix='auto'
uci -q set network.lan6.norelease='1'
uci -q set network.lan6.sourcefilter='0'
uci -q set network.lan6.delegate='0'
uci commit network

# --- 3. 关闭 DHCP 服务 (旁路由必须关闭) ---
uci -q set dhcp.lan.ignore='1'
# 彻底关闭 IPv6 的 DHCP/RA 响应，防止干扰主路由
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
# 查找名为 'lan' 的 firewall zone 索引，并将 lan6 接口加入其中
ZONE_IDX=$(uci show firewall | grep -E "name='lan'$" | cut -d'.' -f2 | cut -d'=' -f1 | head -n 1)
if [ -n "$ZONE_IDX" ]; then
    # 清空原有的 network 列表并重新添加 lan 和 lan6
    uci -q delete firewall.${ZONE_IDX}.network
    uci add_list firewall.${ZONE_IDX}.network='lan'
    uci add_list firewall.${ZONE_IDX}.network='lan6'
    uci commit firewall
fi

# --- 6. 应用配置 ---
# 首次开机应用完配置后，重启网络和防火墙使其立即生效
/etc/init.d/network restart
/etc/init.d/firewall restart

exit 0
SCRIPT_EOF

chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

echo "🎉 DIY 脚本全部执行完毕！"
