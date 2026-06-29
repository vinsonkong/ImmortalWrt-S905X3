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

echo "🎨 2. 修改 config_generate (作为 Fallback 兜底)..."
sed -i 's/192.168.1.1/192.168.30.254/g' package/base-files/files/bin/config_generate
sed -i 's/ImmortalWrt/X96Max/g' package/base-files/files/bin/config_generate
sed -i "s/'UTC'/'CST-8'\n   set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate

echo "🔧 3. 开始静态注入所有 /etc/config 基础配置 (彻底抛弃 uci-defaults)..."
mkdir -p package/base-files/files/etc/config
mkdir -p package/base-files/files/etc/dropbear

# ================= [ 3.1 网络配置 (network) ] =================
cat > package/base-files/files/etc/config/network <<'EOF'
config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'auto'

config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.30.254'
    option netmask '255.255.255.0'
    option gateway '192.168.30.1'
    option delegate '0'
    list dns '223.5.5.5'
    list dns '114.114.114.114'
    list dns '8.8.8.8'

config interface 'lan6'
    option proto 'dhcpv6'
    option device 'br-lan'
    option reqaddress 'try'
    option reqprefix 'auto'
    option norelease '1'
    option sourcefilter '0'
    option delegate '0'
EOF

# ================= [ 3.2 DHCP 配置 (dhcp) ] =================
cat > package/base-files/files/etc/config/dhcp <<'EOF'
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

# ================= [ 3.3 系统配置 (system) ] =================
cat > package/base-files/files/etc/config/system <<'EOF'
config system
    option hostname 'X96Max'
    option timezone 'CST-8'
    option zonename 'Asia/Shanghai'
    option ttylogin '0'
    option log_size '64'
    option urandom_seed '0'

config timeserver 'ntp'
    option enabled '1'
    option enable_server '0'
    list server 'ntp1.aliyun.com'
    list server 'ntp2.aliyun.com'
    list server 'ntp3.aliyun.com'
    list server 'ntp4.aliyun.com'
EOF

# ================= [ 3.4 uhttpd 配置 ] =================
# 自动寻找 uhttpd 默认配置路径并覆盖
UHTTPD_PATH="package/network/services/uhttpd/files/uhttpd.config"
if [ ! -f "$UHTTPD_PATH" ]; then
    UHTTPD_PATH="package/base-files/files/etc/config/uhttpd"
fi
mkdir -p $(dirname "$UHTTPD_PATH")

cat > "$UHTTPD_PATH" <<'EOF'
config uhttpd 'main'
    list listen_http '0.0.0.0:80'
    list listen_http '[::]:80'
    option redirect_https '0'
    option home '/www'
    option rfc1918_filter '1'
    option max_connections '100'
    option cert '/etc/uhttpd.crt'
    option key '/etc/uhttpd.key'
    option cgi_prefix '/cgi-bin'
    list lua_prefix '/cgi-bin/luci=/usr/lib/lua/luci/sgi/uhttpd.lua'
    option network_timeout '30'
    option http_keepalive '20'
    option tcp_keepalive '1'
    option ubus_prefix '/ubus'
    list index_page 'cgi-bin/luci'
    option max_requests '50'
    option script_timeout '3600'

config uhttpd 'web'
    list listen_http '0.0.0.0:39380'
    list listen_http '[::]:39380'
    option redirect_https '0'
    option home '/mnt/mmcblk2p4/webguide'
    list interpreter '.php=/usr/bin/php-cgi'
    option script_timeout '60'
    option index_page 'index.php index.html'

config cert 'defaults'
    option days '730'
    option key_type 'ec'
    option bits '2048'
    option ec_curve 'P-256'
    option country 'ZZ'
    option state 'Somewhere'
    option location 'Unknown'
    option commonname 'OpenWrt'
EOF

# ================= [ 3.5 ZeroTier 配置 ] =================
cat > package/base-files/files/etc/config/zerotier <<'EOF'
config zerotier 'earth'
    option id '9f77fc393e652048'
    option enabled '1'
EOF

# ================= [ 3.6 Dropbear SSH 配置与公钥 ] =================
cat > package/base-files/files/etc/config/dropbear <<'EOF'
config dropbear
    option PasswordAuth 'on'
    option RootPasswordAuth 'on'
    option RootLogin '1'
    option Port '22'
EOF

cat > package/base-files/files/etc/dropbear/authorized_keys <<'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDg995BH9wmXnqi+voUaQT0oSYi+guKytDzJBMe0psHZDC1APuG5T1dfRdQzK2STWx3gq/b9cG8H9wm6KtSiQsTjQkvfVyuLSe4u9f0BChBEbUcfpvjt51Lnkobyo5Ppnj9l3v8TMehdVMcMluNciF8HxTJwrtuPiKcfLeqqUvzSU0wUdvkdq+rirusEhK45mzBZBmCDUq6fECxdEcKKCFmOUHM6CWdXJnAWk1ehchy+EGxMri5fG6uMJh4Y43vjVBYavN0aqW37ASkUe9LXuokYm0W2gBVzoZuCHBw09roPEeZvJYhSjdVrfmYXbi1qoyaHMjT0zSTSt6ov/WFfI+n x96max
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4un4qvoUbhkmaOvIEvRWZ5qlSrrqzRpUb8BsKn65bn x96max+
EOF

# ================= [ 3.7 动态逻辑移入 rc.local ] =================
# 由于 opkg 源依赖运行时的内核版本，且 dropbear 需要修复权限，将其放入 rc.local
cat > package/base-files/files/etc/rc.local <<'EOF'
#!/bin/sh
# rc.local - 每次启动执行

# 1. 修复 Dropbear 公钥权限 (防止编译打包时权限丢失)
chmod 700 /etc/dropbear 2>/dev/null
chmod 600 /etc/dropbear/authorized_keys 2>/dev/null

# 2. 动态添加 ImmortalWrt kmods 源
KMODS_MARKER="immortalwrt_kmods"
if ! grep -q "$KMODS_MARKER" /etc/opkg/distfeeds.conf 2>/dev/null; then
    KERNEL_VER=$(uname -r)
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64) TARGET_PATH="targets/armsr/armv8" ;;
        x86_64)  TARGET_PATH="targets/x86/64" ;;
        *)       TARGET_PATH="" ;;
    esac
    
    if [ -n "$TARGET_PATH" ]; then
        IW_VERSION=$(grep -oE 'DISTRIB_RELEASE="[0-9.]+"' /etc/openwrt_release | cut -d'"' -f2)
        [ -z "$IW_VERSION" ] && IW_VERSION="24.10.6"
        KMODS_URL="https://mirrors.ustc.edu.cn/immortalwrt/releases/${IW_VERSION}/${TARGET_PATH}/kmods/${KERNEL_VER}"
        
        echo "# ImmortalWrt kmods (auto-added)" >> /etc/opkg/distfeeds.conf
        echo "src/gz immortalwrt_kmods ${KMODS_URL}" >> /etc/opkg/distfeeds.conf
    fi
fi

exit 0
EOF

echo "✅ 所有基础配置已静态注入完毕！彻底告别 uci-defaults 不生效的问题。"
