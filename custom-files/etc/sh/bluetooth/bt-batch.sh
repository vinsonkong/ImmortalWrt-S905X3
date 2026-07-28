#!/bin/sh
# 用法: ./bt-batch.sh pair   (执行批量配对和信任)
#       ./bt-batch.sh connect (执行批量连接)

MAC_FILE="/etc/sh/bluetooth/mac.txt"
ACTION=$1

# 检查参数
if [ -z "$ACTION" ]; then
    echo "用法: $0 {pair|connect}"
    exit 1
fi

# 检查文件
if [ ! -f "$MAC_FILE" ]; then
    echo "错误: 找不到 $MAC_FILE"
    exit 1
fi

# 确保蓝牙开启
bluetoothctl power on > /dev/null 2>&1
hciconfig hci0 up 2>/dev/null

echo "开始执行动作: $ACTION ..."

# 使用 grep 过滤有效 MAC 地址：
# -v '^#' : 排除注释行
# -v '^$' : 排除空行
# sed 's/[[:space:]]//g' : 去除所有空格
VALID_MACS=$(grep -v '^#' "$MAC_FILE" | grep -v '^$' | sed 's/[[:space:]]//g')

if [ -z "$VALID_MACS" ]; then
    echo "未找到有效的 MAC 地址"
    exit 1
fi

for MAC in $VALID_MACS; do
    echo "----------------------------------------"
    echo "处理设备: $MAC"
    
    if [ "$ACTION" = "pair" ]; then
        # 配对并信任
        bluetoothctl <<EOF
agent on
default-agent
scan on
sleep 10
pair $MAC
trust $MAC
scan off
quit
EOF
        echo "[$MAC] 配对与信任指令已发送"
        
    elif [ "$ACTION" = "connect" ]; then
        # 尝试连接
        RESULT=$(bluetoothctl connect $MAC 2>&1)
        if echo "$RESULT" | grep -q "Connection successful"; then
            echo "[$MAC] ✅ 连接成功"
        else
            echo "[$MAC] ❌ 连接失败或已连接"
        fi
    fi
    
    # 短暂延迟，防止蓝牙栈过载
    sleep 1
done

echo "----------------------------------------"
echo "任务完成"
