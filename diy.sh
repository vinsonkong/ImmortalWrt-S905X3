#!/bin/bash

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
DEFAULT_PACKAGES += luci-theme-argon
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


echo "🔧 3. 注入 99-custom-settings ..."
mkdir -p package/base-files/files/etc/uci-defaults

cat <<'SCRIPT_EOF' > package/base-files/files/etc/uci-defaults/99-custom-settings
#!/bin/sh
# =========================================================
# 旁路由初始化脚本 
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

# --- 5. 时区软链接 ---
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime


# --- 6. 重置 uhttpd 配置
uci -q delete uhttpd

uci -q batch << 'UCIBATCH'
# === main 实例 (LuCI 主站) ===
set uhttpd.main=uhttpd
add_list uhttpd.main.listen_http='0.0.0.0:80'
add_list uhttpd.main.listen_http='[::]:80'
add_list uhttpd.main.listen_https=''
set uhttpd.main.redirect_https='0'
set uhttpd.main.home='/www'
set uhttpd.main.rfc1918_filter='1'
set uhttpd.main.max_connections='100'
set uhttpd.main.cert='/etc/uhttpd.crt'
set uhttpd.main.key='/etc/uhttpd.key'
set uhttpd.main.cgi_prefix='/cgi-bin'
add_list uhttpd.main.lua_prefix='/cgi-bin/luci=/usr/lib/lua/luci/sgi/uhttpd.lua'
set uhttpd.main.network_timeout='30'
set uhttpd.main.http_keepalive='20'
set uhttpd.main.tcp_keepalive='1'
set uhttpd.main.ubus_prefix='/ubus'
add_list uhttpd.main.index_page='cgi-bin/luci'
set uhttpd.main.max_requests='50'
set uhttpd.main.script_timeout='3600'

# === web 实例  ===
set uhttpd.web=uhttpd
add_list uhttpd.web.listen_http='0.0.0.0:39380'
add_list uhttpd.web.listen_http='[::]:39380'
set uhttpd.web.redirect_https='0'
set uhttpd.web.home='/mnt/mmcblk2p4/webguide'
add_list uhttpd.web.interpreter='.php=/usr/bin/php-cgi'
set uhttpd.web.script_timeout='60'
set uhttpd.web.index_page='index.php index.html'

# === 自签证书默认参数 ===
set uhttpd.defaults=cert
set uhttpd.defaults.days='730'
set uhttpd.defaults.key_type='ec'
set uhttpd.defaults.bits='2048'
set uhttpd.defaults.ec_curve='P-256'
set uhttpd.defaults.country='ZZ'
set uhttpd.defaults.state='Somewhere'
set uhttpd.defaults.location='Unknown'
set uhttpd.defaults.commonname='OpenWrt'
commit uhttpd
UCIBATCH

#  重启 uhttpd 使配置立即生效
/etc/init.d/uhttpd restart 2>/dev/null

#  修改zerotier配置
uci -q set zerotier.earth.id='9f77fc393e652048'



SCRIPT_EOF

# 给脚本添加执行权限
chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

echo "=== 🔥 注入 Ext4/Btrfs 下的恢复出厂设置脚本 (Hack LuCI) ==="
# 创建 firstboot 脚本，LuCI 检测到它存在就会显示“恢复出厂”按钮
mkdir -p package/base-files/files/sbin
cat << 'EOF' > package/base-files/files/sbin/firstboot
#!/bin/sh
# 专为 Ext4/Btrfs 固件定制的恢复出厂脚本
echo "Performing factory reset on Ext4/Btrfs..."

# 1. 清理用户配置
rm -rf /etc/config/*
rm -rf /etc/dropbear
rm -rf /etc/ssh
rm -rf /etc/shadow*
rm -rf /etc/passwd*

# 2. 清理 overlay (如果存在)
if [ -d "/overlay" ]; then
    rm -rf /overlay/upper/*
    rm -rf /overlay/work/*
fi

# 3. 重启设备
echo "System will reboot now..."
reboot
EOF

# 赋予执行权限
chmod +x package/base-files/files/sbin/firstboot
echo "✅ /sbin/firstboot 注入成功！LuCI 将显示恢复出厂按钮。"



echo " diy.sh 执行完毕"
