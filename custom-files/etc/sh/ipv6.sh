#!/bin/bash

# 配置项
TITLE="x96max"
INTERFACE="br-lan"
STATE="/tmp/last_ipv6.txt"
JSON_FILE="/www/webguide/addr/ipv6.json"


# 加载 jshn.sh 库
. /usr/share/libubox/jshn.sh 2>/dev/null || {
    echo "错误：无法加载jshn库" >&2
    exit 1
}

# 提取接口的全球单播 IPv6 地址
NEW=$(ip -6 addr show dev "$INTERFACE" scope global 2>/dev/null | 
      grep -oE '([0-9a-f:]+/[0-9]+)' | 
      head -1 | 
      cut -d'/' -f1)

# 如果第一种方式没找到，尝试第二种方式
if [[ -z "$NEW" ]]; then
    NEW=$(ip -6 addr show dev "$INTERFACE" scope global | 
          grep -E 'inet6 [2-7][0-9a-f:]+/64' | 
          grep -v 'fe80' | 
          awk '{print $2}' | 
          cut -d'/' -f1 | 
          head -n1)
fi

DHCPV6=$(ip -6 addr show dev "$INTERFACE" scope global | 
         grep -E 'inet6 24[0-9a-f:]+/128' | 
         awk '{print $2}' | 
         cut -d'/' -f1 | 
         head -n1)

if [[ -z "$NEW" ]]; then
    NEW="$DHCPV6"
fi

[[ -z "$NEW" ]] && {
    echo "未找到IPv6地址"
    exit 0
}

[[ -f "$STATE" ]] && OLD=$(cat "$STATE" 2>/dev/null)
[[ "$NEW" == "$OLD" ]] && {
    echo "IPv6地址未变化：$NEW"
    exit 0
}

#echo "检测到IPv6地址变化: ${OLD:-无} -> $NEW"

# 读取JSON文件
if [[ ! -f "$JSON_FILE" ]]; then
    echo "错误：JSON文件不存在 $JSON_FILE" >&2
    exit 1
fi

json_content=$(cat "$JSON_FILE")
if [[ -z "$json_content" ]]; then
    echo "错误：JSON文件为空" >&2
    exit 1
fi

# 使用sed直接替换JSON文件中的IPv6地址
# 注意：JSON文件中的反斜杠转义需要处理
sed -i "/x96maxDHCPV6/{n; s#\"url\": \"http://\[.*\]#\"url\": \"http://\[$DHCPV6\]#g}" "$JSON_FILE"
sed -i "/x96maxipv6/{n; s#\"url\": \"http://\[.*\]#\"url\": \"http://\[$NEW\]#g}" "$JSON_FILE"


# 保存新地址
echo "$NEW" > "$STATE"
echo "IPv6地址已更新并记录: $NEW"

