#!/bin/bash

# ==============================================================================
# 脚本名称: bt-batch.sh
# 功能描述: 批量处理蓝牙设备的配对、信任或连接
# 用法: 
#   sudo ./bt-batch.sh pair     # 批量配对并信任
#   sudo ./bt-batch.sh connect  # 批量连接已配对设备
# 依赖文件: /etc/sh/bluetooth/mac.txt (每行一个 MAC 地址)
# ==============================================================================

MAC_FILE="/etc/sh/bluetooth/mac.txt"
ACTION=$1

# --- 1. 基础检查 ---

# 检查是否以 root 运行 (蓝牙控制通常需要特权)
if [ "$(id -u)" -ne 0 ]; then
    echo "警告: 建议以 root 权限运行此脚本 (sudo ./bt-batch.sh ...)"
fi

# 检查 bluetoothctl 是否存在
if ! command -v bluetoothctl &> /dev/null; then
    echo "错误: 未找到 bluetoothctl 命令，请安装 bluez-utils"
    exit 1
fi

# 检查参数
if [ -z "$ACTION" ]; then
    echo "用法: $0 {pair|connect}"
    exit 1
fi

if [ "$ACTION" != "pair" ] && [ "$ACTION" != "connect" ]; then
    echo "错误: 未知动作 '$ACTION'。请使用 'pair' 或 'connect'"
    exit 1
fi

# 检查文件
if [ ! -f "$MAC_FILE" ]; then
    echo "错误: 找不到配置文件 $MAC_FILE"
    exit 1
fi

# --- 2. 初始化蓝牙适配器 ---

echo "正在初始化蓝牙适配器..."
# 尝试开启蓝牙电源
bluetoothctl power on > /dev/null 2>&1
# 尝试启用 hci0 (兼容旧系统或特定驱动)
hciconfig hci0 up 2>/dev/null

# 短暂等待适配器就绪
sleep 2

# --- 3. 读取并验证 MAC 地址 ---

# 定义 MAC 地址正则表达式 (匹配 XX:XX:XX:XX:XX:XX 或 XX-XX-XX-XX-XX-XX)
MAC_REGEX="^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"

# 读取文件，过滤注释和空行，去除空格
VALID_MACS=()
while IFS= read -r line; do
    # 去除首尾空白
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 跳过空行和注释
    if [[ -z "$line" || "$line" == \#* ]]; then
        continue
    fi
    
    # 校验 MAC 格式
    if [[ $line =~ $MAC_REGEX ]]; then
        # 统一转换为大写冒号格式 (可选，bluetoothctl 通常不区分大小写和分隔符)
        VALID_MACS+=("$line")
    else
        echo "警告: 跳过无效 MAC 地址格式: $line"
    fi
done < "$MAC_FILE"

if [ ${#VALID_MACS[@]} -eq 0 ]; then
    echo "错误: 文件中未找到有效的 MAC 地址"
    exit 1
fi

echo "找到 ${#VALID_MACS[@]} 个有效设备。开始执行动作: $ACTION ..."
echo "----------------------------------------"

# --- 4. 执行动作 ---

if [ "$ACTION" = "pair" ]; then
    # === 配对模式 ===
    
    # 全局开启扫描 (避免在每个设备循环中重复开关扫描，提高效率)
    echo "开启全局扫描..."
    bluetoothctl scan on > /dev/null 2>&1
    
    # 给扫描一点时间来发现设备
    echo "等待设备发现 (15秒)..."
    sleep 15
    
    for MAC in "${VALID_MACS[@]}"; do
        echo "处理设备: $MAC"
        
        # 使用 heredoc 发送配对和信任指令
        # 注意: sleep 不能在 bluetoothctl 内部使用，必须在外部控制节奏
        OUTPUT=$(bluetoothctl <<EOF
agent on
default-agent
pair $MAC
trust $MAC
quit
EOF
)
        # 检查输出中是否包含成功关键词
        if echo "$OUTPUT" | grep -qi "Pairing successful"; then
            echo "[$MAC] ✅ 配对成功"
        elif echo "$OUTPUT" | grep -qi "Already paired"; then
            echo "[$MAC] ℹ️  已配对，继续信任"
        else
            echo "[$MAC] ❌ 配对失败或超时"
            echo "   调试信息: $OUTPUT"
        fi
        
        # 确保信任指令生效 (有时配对成功后 trust 需要单独确认)
        # 这里再次发送 trust 确保万无一失
        bluetoothctl trust $MAC > /dev/null 2>&1
        
        # 延迟，防止蓝牙栈拥堵
        sleep 2
    done
    
    # 关闭扫描
    echo "关闭全局扫描..."
    bluetoothctl scan off > /dev/null 2>&1

elif [ "$ACTION" = "connect" ]; then
    # === 连接模式 ===
    
    for MAC in "${VALID_MACS[@]}"; do
        echo "处理设备: $MAC"
        
        # 尝试连接
        RESULT=$(bluetoothctl connect $MAC 2>&1)
        
        # 判断结果：成功连接 或 已经连接
        if echo "$RESULT" | grep -qi "Connection successful"; then
            echo "[$MAC] ✅ 连接成功"
        elif echo "$RESULT" | grep -qi "Already connected"; then
            echo "[$MAC] ℹ️  设备已连接"
        else
            echo "[$MAC] ❌ 连接失败"
            # 可选：打印错误详情以便调试
            # echo "   错误详情: $RESULT"
        fi
        
        # 延迟，防止蓝牙栈拥堵
        sleep 1
    done
fi

echo "----------------------------------------"
echo "任务完成"
exit 0
