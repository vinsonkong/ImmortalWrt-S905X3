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
