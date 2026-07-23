# 1. 更新软件包列表（失败则终止，避免后续错误）
opkg update || exit 1

# 2. 进入临时目录并下载官方安装脚本
cd /tmp
wget https://github.com/linkease/openwrt-app-actions/raw/main/applications/luci-app-systools/root/usr/share/systools/istore-reinstall.run

# 3. 赋予执行权限并运行
chmod 755 istore-reinstall.run
./istore-reinstall.run
