#!/bin/sh
# =============================================================================
# Universal System Info MOTD Script (Final Fixed Version)
# Compatible with: OpenWrt, Debian, Ubuntu, Armbian, Alpine, etc.
# Architecture:    x86_64, AArch64, ARMv7, RISC-V, MIPS
# Shell:           POSIX sh (ash/bash/dash/zsh)
# =============================================================================

# ------------------------- Configuration ------------------------------------
SHOW_IP_PATTERN="^[ewbrltuw].*|^docker.*|^wg.*|^tun.*"
TEMP_WARN=70        # Temperature warning threshold (°C)
LOAD_WARN_FACTOR=2  # Load warning = CPU cores * this factor
# ----------------------------------------------------------------------------

# Color definitions (ANSI)
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
CYAN='\033[0;96m'
RESET='\033[0m'

# ------------------------- Helper Functions ---------------------------------

get_cpu_cores() {
    grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1
}

get_uptime() {
    if [ -f /proc/uptime ]; then
        raw=$(awk '{print int($1)}' /proc/uptime)
        days=$((raw / 86400))
        hours=$(( (raw % 86400) / 3600 ))
        mins=$(( (raw % 3600) / 60 ))
        secs=$((raw % 60))
        if [ "$days" -gt 0 ]; then
            printf "%dd %dh %dm %ds" "$days" "$hours" "$mins" "$secs"
        elif [ "$hours" -gt 0 ]; then
            printf "%dh %dm %ds" "$hours" "$mins" "$secs"
        else
            printf "%dm %ds" "$mins" "$secs"
        fi
    else
        echo "N/A"
    fi
}

get_load_avg() {
    if [ -f /proc/loadavg ]; then
        awk '{print $1, $2, $3}' /proc/loadavg
    else
        echo "N/A"
    fi
}

get_cpu_temp() {
    temp=""
    for f in /sys/class/hwmon/hwmon*/temp1_input; do
        [ -r "$f" ] && temp=$(cat "$f" 2>/dev/null) && break
    done
    if [ -z "$temp" ]; then
        for f in /sys/class/thermal/thermal_zone*/temp; do
            [ -r "$f" ] && temp=$(cat "$f" 2>/dev/null) && break
        done
    fi
    
    if [ -n "$temp" ] && [ "$temp" -gt 0 ] 2>/dev/null; then
        if [ "$temp" -gt 1000 ]; then
            whole=$((temp / 1000))
            frac=$(( (temp % 1000) / 100 ))
            printf "%d.%d°C" "$whole" "$frac"
        else
            printf "%d°C" "$temp"
        fi
    else
        echo "N/A"
    fi
}

get_cpu_freq() {
    freq_file="/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq"
    if [ -r "$freq_file" ]; then
        freq=$(cat "$freq_file" 2>/dev/null)
        if [ -n "$freq" ] && [ "$freq" -gt 0 ] 2>/dev/null; then
            mhz=$((freq / 1000))
            printf "%d MHz" "$mhz"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_device_model() {
    model=""
    # x86/x64 DMI
    if [ -f /sys/class/dmi/id/product_name ]; then
        model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    # ARM / AArch64 / RISC-V Device Tree
    elif [ -f /proc/device-tree/model ]; then
        model=$(tr -d '\000' < /proc/device-tree/model 2>/dev/null)
    # OpenWrt board.json
    elif [ -f /etc/board.json ]; then
        model=$(awk -F'"' '/"model"/{print $4; exit}' /etc/board.json 2>/dev/null)
    fi
    
    if [ -z "$model" ]; then
        model=$(uname -n 2>/dev/null)
    fi
    
    echo "$model" | sed 's/[[:space:]]*$//' | tr -d '\r\n'
}

# [FIX] 强制移除所有非打印字符并压缩空格，防止异常换行
get_arch() {
    arch=$(uname -m 2>/dev/null)
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null \
        | cut -d: -f2 \
        | sed 's/[^[:print:]]//g; s/[[:space:]]\+/ /g; s/^ //; s/ $//')
    if [ -n "$cpu_model" ]; then
        printf "%s : %s" "$arch" "$cpu_model"
    else
        echo "$arch"
    fi
}

get_mem_info() {
    if [ -f /proc/meminfo ]; then
        total=$(awk '/^MemTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo)
        avail=$(awk '/^MemAvailable:/ {printf "%.0f", $2/1024}' /proc/meminfo)
        if [ -z "$avail" ]; then
            free=$(awk '/^MemFree:/ {printf "%.0f", $2/1024}' /proc/meminfo)
            buffers=$(awk '/^Buffers:/ {printf "%.0f", $2/1024}' /proc/meminfo)
            cached=$(awk '/^Cached:/ {printf "%.0f", $2/1024}' /proc/meminfo)
            avail=$((free + buffers + cached))
        fi
        used=$((total - avail))
        if [ "$total" -gt 0 ] 2>/dev/null; then
            pct=$((used * 100 / total))
        else
            pct=0
        fi
        printf "%d|%d|%d" "$pct" "$used" "$total"
    else
        echo "0|0|0"
    fi
}

get_swap_info() {
    if [ -f /proc/meminfo ]; then
        total=$(awk '/^SwapTotal:/ {printf "%.0f", $2/1024}' /proc/meminfo)
        free=$(awk '/^SwapFree:/ {printf "%.0f", $2/1024}' /proc/meminfo)
        used=$((total - free))
        if [ "$total" -gt 0 ] 2>/dev/null; then
            pct=$((used * 100 / total))
        else
            pct=0
        fi
        printf "%d|%d|%d" "$pct" "$used" "$total"
    else
        echo "0|0|0"
    fi
}

get_storage() {
    mount_point="$1"
    info=$(df -h "$mount_point" 2>/dev/null | tail -n1)
    if [ -n "$info" ]; then
        usage=$(echo "$info" | awk '{gsub(/%/,""); print $(NF-1)}')
        total=$(echo "$info" | awk '{print $(NF-4)}')
        printf "%s|%s" "$usage" "$total"
    else
        echo "0|N/A"
    fi
}

# [FIX] 多 IP 自动换行对齐，避免终端宽度溢出
get_ip_addresses() {
    ips=""
    count=0
    for iface_path in /sys/class/net/*; do
        iface=$(basename "$iface_path")
        case "$iface" in lo) continue ;; esac
        if echo "$iface" | grep -qE "$SHOW_IP_PATTERN"; then
            ip=$(ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]}')
            if [ -n "$ip" ]; then
                count=$((count + 1))
                if [ "$count" -gt 1 ] && [ $(( (count - 1) % 3 )) -eq 0 ]; then
                    ips="${ips}\n              "
                fi
                ips="${ips:+$ips }${ip}"
            fi
        fi
    done
    if [ -z "$ips" ]; then
        echo "N/A"
    else
        printf "%b" "$ips"
    fi
}

color_value() {
    val="$1"
    warn_threshold="$2"
    unit="$3"
    if [ "$val" = "N/A" ]; then
        printf "${CYAN}%s${RESET}" "N/A"
    elif [ "$val" -ge "$warn_threshold" ] 2>/dev/null; then
        printf "${RED}%s%s${RESET}" "$val" "$unit"
    else
        printf "${GREEN}%s%s${RESET}" "$val" "$unit"
    fi
}

# ------------------------- Main Display -------------------------------------

cores=$(get_cpu_cores)
load_warn=$((cores * LOAD_WARN_FACTOR))
load=$(get_load_avg)
load_1=$(echo "$load" | awk '{print $1}')

mem_data=$(get_mem_info)
mem_pct=$(echo "$mem_data" | cut -d'|' -f1)
mem_used=$(echo "$mem_data" | cut -d'|' -f2)
mem_total=$(echo "$mem_data" | cut -d'|' -f3)

swap_data=$(get_swap_info)
swap_pct=$(echo "$swap_data" | cut -d'|' -f1)
swap_used=$(echo "$swap_data" | cut -d'|' -f2)
swap_total=$(echo "$swap_data" | cut -d'|' -f3)

boot_data=$(get_storage "/boot")
boot_pct=$(echo "$boot_data" | cut -d'|' -f1)
boot_total=$(echo "$boot_data" | cut -d'|' -f2)

root_data=$(get_storage "/")
root_pct=$(echo "$root_data" | cut -d'|' -f1)
root_total=$(echo "$root_data" | cut -d'|' -f2)

temp_formatted=$(get_cpu_temp)
temp_num=$(echo "$temp_formatted" | grep -oE '^[0-9]+')

echo "───────────────────────────────────────────────────────────────────────"
printf " Device Model : ${YELLOW}%s${RESET}\n" "$(get_device_model)"
printf " Architecture : ${YELLOW}%s${RESET}\n" "$(get_arch)"
printf " Load Average : "; color_value "$load_1" "$load_warn" ""; printf "  %s\n" "$(echo "$load" | awk '{print $2, $3}')"
printf " Uptime       : ${GREEN}%s${RESET}\n" "$(get_uptime)"
printf " Ambient Temp : "; color_value "${temp_num:-0}" "$TEMP_WARN" "°C"; printf "\n"
printf " CPU Freq     : ${GREEN}%s${RESET}\n" "$(get_cpu_freq)"
printf " Memory Usage : "; color_value "$mem_pct" "80" "%"; printf " of %sM (Used: %sM)\n" "$mem_total" "$mem_used"
printf " Swap Usage   : "; color_value "$swap_pct" "80" "%"; printf " of %sM (Used: %sM)\n" "$swap_total" "$swap_used"
printf " Boot Storage : "; color_value "$boot_pct" "90" "%"; printf " of %s\n" "$boot_total"
printf " Root FS      : "; color_value "$root_pct" "90" "%"; printf " of %s\n" "$root_total"
printf " IP Addresses : ${GREEN}%s${RESET}\n" "$(get_ip_addresses)"
echo "───────────────────────────────────────────────────────────────────────"
