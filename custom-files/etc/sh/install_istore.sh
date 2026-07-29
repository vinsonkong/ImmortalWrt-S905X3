#!/bin/sh
# iStore 应用商店一键安装脚本 (本地运行版)
# 适用系统: OpenWrt / iStoreOS (19.07+ / 21.x / 23.x / 25.x APK)

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== 前置检查 ==========
check_env() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本！"
        exit 1
    fi

    if ! command -v opkg >/dev/null 2>&1 && ! command -v apk >/dev/null 2>&1; then
        log_error "未检测到 opkg 或 apk 包管理器，请确认当前系统为 OpenWrt/iStoreOS"
        exit 1
    fi

    # 检查架构
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|aarch64|arm64) log_info "检测到架构: $ARCH ✓" ;;
        *) log_warn "架构 $ARCH 可能不受官方支持，安装可能失败" ;;
    esac
}

# ========== 多源下载函数 ==========
download_script() {
    TARGET="/tmp/istore-reinstall.run"
    SOURCES="
        https://github.com/linkease/openwrt-app-actions/raw/main/applications/luci-app-systools/root/usr/share/systools/istore-reinstall.run
        https://gitcode.com/gh_mirrors/is/istore/raw/main/installer/istore-installer.run
        https://mirror.ghproxy.com/https://raw.githubusercontent.com/linkease/openwrt-app-actions/main/applications/luci-app-systools/root/usr/share/systools/istore-reinstall.run
    "

    for url in $SOURCES; do
        log_info "尝试下载: $url"
        if wget -q --timeout=15 --tries=2 -O "$TARGET" "$url" 2>/dev/null; then
            if [ -s "$TARGET" ]; then
                log_info "下载成功 ✓"
                chmod 755 "$TARGET"
                return 0
            fi
        fi
        log_warn "该源下载失败，尝试下一个..."
    done

    log_error "所有下载源均失败，请检查网络连接或手动下载安装脚本"
    exit 1
}

# ========== 安装依赖 ==========
install_deps() {
    log_info "更新软件包列表..."
    if command -v apk >/dev/null 2>&1; then
        apk update || true
    else
        opkg update || true
        # OpenWrt 21.x 需要 luci-compat
        if opkg list-installed | grep -q "luci-compat"; then
            log_info "luci-compat 已安装"
        else
            log_info "安装 luci-compat 兼容层..."
            opkg install luci-compat || log_warn "luci-compat 安装失败，部分旧版插件可能无法显示"
        fi
    fi
}

# ========== 主流程 ==========
main() {
    echo "========================================="
    echo "   iStore 应用商店 一键安装脚本"
    echo "========================================="
    echo ""

    check_env
    install_deps
    download_script

    log_info "开始执行 iStore 安装程序..."
    echo "-----------------------------------------"
    /tmp/istore-reinstall.run
    INSTALL_STATUS=$?
    echo "-----------------------------------------"

    if [ $INSTALL_STATUS -eq 0 ]; then
        log_info "🎉 iStore 安装完成！"
        log_info "请刷新浏览器 LuCI 页面查看 iStore 菜单"
        log_info "如未显示，请尝试: 清除浏览器缓存 / 重启路由器(reboot)"
    else
        log_error "安装过程中出现错误 (退出码: $INSTALL_STATUS)"
        log_error "请检查上方日志输出，或前往 https://github.com/linkease/istore/issues 反馈"
    fi

    # 清理临时文件
    rm -f /tmp/istore-reinstall.run
}

main "$@"

