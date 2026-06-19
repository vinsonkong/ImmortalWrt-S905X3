#!/bin/bash

# 1. 修改默认 IP 地址 (改为 192.168.2.1，避免与光猫冲突)
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# 2. 修改默认主机名
sed -i 's/ImmortalWrt/X96Max-Router/g' package/base-files/files/bin/config_generate

# 3. 添加第三方软件源 (kenzok8 常用插件包，包含 PassWall, OpenClash 等)
git clone --depth 1 https://github.com/kenzok8/openwrt-packages.git package/kenzok8
git clone --depth 1 https://github.com/kenzok8/small.git package/small

# 4. 添加 Docker 支持相关依赖 (如果 .config 中开启了 Docker)
# 通常 feeds 中已包含，此处无需额外操作

echo "DIY script execution completed!"
