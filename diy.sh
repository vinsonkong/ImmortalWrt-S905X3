#!/bin/bash

echo "🚀 1. 开始执行 Target 层白名单清理.."
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
# 旁路由初始化脚本 (仅在设备首次启动时执行)
# =========================================================

# --- 1. 网络配置 (旁路由核心) ---
uci -q set network.lan.proto='static'
uci -q set network.lan.ipaddr='192.168.30.254'
uci -q set network.lan.netmask='255.255.255.0'
uci -q set network.lan.gateway='192.168.30.1'

# 24.10+ 强制使用 device，彻底废弃 ifname 避免警告
uci -q set network.lan.device='br-lan'
uci -q delete network.lan.ifname 2>/dev/null

# DNS 与委托配置
uci -q delete network.lan.dns 2>/dev/null
uci -q add_list network.lan.dns='223.5.5.5'
uci -q add_list network.lan.dns='114.114.114.114'
uci -q add_list network.lan.dns='8.8.8.8'
uci -q set network.lan.delegate='0'

# --- 2. IPv6 穿透配置 ---
uci -q delete network.lan6 2>/dev/null
uci -q set network.lan6=interface
uci -q set network.lan6.proto='dhcpv6'
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
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# --- 5. 重置 uhttpd 配置 ---
uci -q delete uhttpd
uci -q batch << 'UCIBATCH'
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

set uhttpd.web=uhttpd
add_list uhttpd.web.listen_http='0.0.0.0:39380'
add_list uhttpd.web.listen_http='[::]:39380'
set uhttpd.web.redirect_https='0'
set uhttpd.web.home='/mnt/mmcblk2p4/webguide'
add_list uhttpd.web.interpreter='.php=/usr/bin/php-cgi'
set uhttpd.web.script_timeout='60'
set uhttpd.web.index_page='index.php index.html'

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
/etc/init.d/uhttpd restart 2>/dev/null

# --- 6. ZeroTier 配置 (带容错守卫) ---
if uci -q get zerotier.earth >/dev/null 2>&1; then
    uci -q set zerotier.earth.id='9f77fc393e652048'
    uci -q commit zerotier
fi

# --- 7. 注入 Dropbear SSH 公钥 ---
SSH_PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDg995BH9wmXnqi+voUaQT0oSYi+guKytDzJBMe0psHZDC1APuG5T1dfRdQzK2STWx3gq/b9cG8H9wm6KtSiQsTjQkvfVyuLSe4u9f0BChBEbUcfpvjt51Lnkobyo5Ppnj9l3v8TMehdVMcMluNciF8HxTJwrtuPiKcfLeqqUvzSU0wUdvkdq+rirusEhK45mzBZBmCDUq6fECxdEcKKCFmOUHM6CWdXJnAWk1ehchy+EGxMri5fG6uMJh4Y43vjVBYavN0aqW37ASkUe9LXuokYm0W2gBVzoZuCHBw09roPEeZvJYhSjdVrfmYXbi1qoyaHMjT0zSTSt6ov/WFfI+n x96max ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4un4qvoUbhkmaOvIEvRWZ5qlSrrqzRpUb8BsKn65bn x96max+"

DROPBEAR_DIR="/etc/dropbear"
AUTH_KEYS="${DROPBEAR_DIR}/authorized_keys"
mkdir -p "$DROPBEAR_DIR"
chmod 700 "$DROPBEAR_DIR"

if ! grep -qF "$SSH_PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
    echo "$SSH_PUBKEY" >> "$AUTH_KEYS"
    echo "✅ SSH 公钥已注入"
fi

chmod 600 "$AUTH_KEYS"
chown root:root "$AUTH_KEYS"
chmod 700 "$DROPBEAR_DIR"
chown root:root "$DROPBEAR_DIR"

uci -q set dropbear.@dropbear[0].PasswordAuth='on'
uci -q set dropbear.@dropbear[0].RootPasswordAuth='on'
uci -q set dropbear.@dropbear[0].RootLogin='1'
uci -q commit dropbear
/etc/init.d/dropbear reload 2>/dev/null

# --- 8. 动态添加 ImmortalWrt kmods 源 (读取系统实际版本) ---
KMODS_MARKER="immortalwrt_kmods"
if ! grep -q "$KMODS_MARKER" /etc/opkg/distfeeds.conf 2>/dev/null; then
    KERNEL_VER=$(uname -r)
    ARCH=$(uname -m)
    
    case "$ARCH" in
        aarch64) TARGET_PATH="targets/armsr/armv8" ;;
        *)       echo "⚠️ 未知架构 $ARCH，跳过 kmods 源添加"; exit 0 ;;
    esac
    
    # 从系统释放文件中动态提取真实版本号，避免硬编码导致跨版本失效
    IW_VERSION=$(grep -oE 'DISTRIB_RELEASE="[0-9.]+"' /etc/openwrt_release | cut -d'"' -f2)
    [ -z "$IW_VERSION" ] && IW_VERSION="24.10.6"
    
    KMODS_URL="https://mirrors.ustc.edu.cn/immortalwrt/releases/${IW_VERSION}/${TARGET_PATH}/kmods/${KERNEL_VER}"
    
    echo "# ImmortalWrt kmods (auto-added)" >> /etc/opkg/distfeeds.conf
    echo "src/gz immortalwrt_kmods ${KMODS_URL}" >> /etc/opkg/distfeeds.conf
    echo "✅ kmods 源已添加: ${KMODS_URL}"
    # 仅写入配置，不阻塞首次启动网络请求
fi

# --- 9. 脚本自删除 (运行时执行，非编译时) ---
rm -f /etc/uci-defaults/99-custom-settings
SCRIPT_EOF

# ✅ 仅赋予执行权限，绝不能在编译阶段 rm 删除此文件！
chmod +x package/base-files/files/etc/uci-defaults/99-custom-settings

echo "✅ diy.sh 执行完毕"
