#!/bin/bash

# 配置项
TITLE="JCG-Q30"
INTERFACE="br-lan"
STATE="/tmp/last_ipv6.txt"
WEB_PORT="39380"
PUSHPLUS_TOKEN="d3ab6649fb294bc8bd2bca56b58b6728"
SERVERCHAN_SENDKEY="SCT351115TJZf2hzUIS9gOckhLJ3SJAYbb"

# 前置检查
command -v curl >/dev/null 2>&1 || { echo "❌ 错误: 未安装 curl"; exit 1; }
[[ "$PUSHPLUS_TOKEN" == "YOUR_"* ]] && PUSHPLUS_TOKEN=""
[[ "$SERVERCHAN_SENDKEY" == "YOUR_"* ]] && SERVERCHAN_SENDKEY=""

# 提取 IPv6 地址
NEW=$(ip -6 addr show dev "$INTERFACE" scope global 2>/dev/null | grep -oE '([0-9a-fA-F:]+/[0-9]+)' | head -1 | cut -d'/' -f1)
if [[ -z "$NEW" ]]; then
    NEW=$(ip -6 addr show dev "$INTERFACE" scope global | grep -E 'inet6 [2-7][0-9a-fA-F:]+/64' | grep -v 'fe80' | awk '{print $2}' | cut -d'/' -f1 | head -n1)
fi

DHCPV6=$(ip -6 addr show dev "$INTERFACE" scope global | grep -E 'inet6 [2-3][0-9a-fA-F:]+/128' | awk '{print $2}' | cut -d'/' -f1 | head -n1)

[[ -z "$NEW" ]] && NEW="$DHCPV6"
[[ -z "$NEW" && -z "$DHCPV6" ]] && { echo "未找到有效的 IPv6 地址"; exit 0; }

# 检查地址变化
CURRENT_STATE="${NEW}|${DHCPV6}"
[[ -f "$STATE" ]] && OLD_STATE=$(cat "$STATE" 2>/dev/null)
[[ "$CURRENT_STATE" == "$OLD_STATE" ]] && { echo "IPv6地址未变化: NEW=$NEW DHCPV6=$DHCPV6"; exit 0; }

OLD_NEW="${OLD_STATE%%|*}"
OLD_DHCP="${OLD_STATE##*|}"
echo "检测到IPv6地址变化:"
echo "  SLAAC:   ${OLD_NEW:-无} -> ${NEW:-无}"
echo "  DHCPv6:  ${OLD_DHCP:-无} -> ${DHCPV6:-无}"

# 构建链接与时间
URL_NEW=""
URL_DHCPV6=""
[[ -n "$NEW" ]] && URL_NEW="http://[${NEW}]:${WEB_PORT}"
[[ -n "$DHCPV6" ]] && URL_DHCPV6="http://[${DHCPV6}]:${WEB_PORT}"
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
CURL_OPTS="-s --connect-timeout 5 --max-time 10"

# PushPlus 推送
if [[ -n "$PUSHPLUS_TOKEN" ]]; then
    PP_CONTENT="<b>📡 ${TITLE} IPv6 地址已更新</b><br/><br/>"
    [[ -n "$URL_NEW" ]] && PP_CONTENT+="<b>前缀地址 (SLAAC):</b><br/><a href=\"${URL_NEW}\">${URL_NEW}</a><br/><br/>"
    [[ -n "$URL_DHCPV6" ]] && PP_CONTENT+="<b>PD地址 (DHCPv6):</b><br/><a href=\"${URL_DHCPV6}\">${URL_DHCPV6}</a><br/><br/>"
    PP_CONTENT+="<font color=\"gray\">更新时间: ${CURRENT_TIME}</font>"

    if command -v jq >/dev/null 2>&1; then
        JSON_PAYLOAD=$(jq -n --arg token "$PUSHPLUS_TOKEN" --arg title "【IPv6更新】${TITLE}" --arg content "$PP_CONTENT" '{token:$token, title:$title, content:$content, template:"html"}')
    else
        ESCAPED_CONTENT=$(printf '%s' "$PP_CONTENT" | sed 's/\\/\\\\/g; s/"/\\"/g')
        JSON_PAYLOAD="{\"token\":\"${PUSHPLUS_TOKEN}\",\"title\":\"【IPv6更新】${TITLE}\",\"content\":\"${ESCAPED_CONTENT}\",\"template\":\"html\"}"
    fi

    PP_RESULT=$(curl $CURL_OPTS -X POST https://www.pushplus.plus/send -H "Content-Type: application/json" -d "$JSON_PAYLOAD" 2>&1)
    echo "$PP_RESULT" | grep -q '"code":200' && echo "✅ PushPlus 推送成功" || echo "❌ PushPlus 推送失败: $PP_RESULT"
fi

# ServerChan 推送
if [[ -n "$SERVERCHAN_SENDKEY" ]]; then
    SC_DESP=$'## 📡 '"${TITLE}"$' IPv6 地址已更新\n\n'
    [[ -n "$URL_NEW" ]] && SC_DESP+=$'**前缀地址 (SLAAC):**\n['"${URL_NEW}"$']('"${URL_NEW}"$')\n\n'
    [[ -n "$URL_DHCPV6" ]] && SC_DESP+=$'**PD地址 (DHCPv6):**\n['"${URL_DHCPV6}"$']('"${URL_DHCPV6}"$')\n\n'
    SC_DESP+=$'> 更新时间: '"${CURRENT_TIME}"

    SC_RESULT=$(curl $CURL_OPTS -X POST "https://sctapi.ftqq.com/${SERVERCHAN_SENDKEY}.send" --data-urlencode "title=【IPv6更新】${TITLE}" --data-urlencode "desp=${SC_DESP}" 2>&1)
    echo "$SC_RESULT" | grep -q '"code":0' && echo "✅ ServerChan 推送成功" || echo "❌ ServerChan 推送失败: $SC_RESULT"
fi

# 保存状态
TMP_STATE="${STATE}.tmp.$$"
echo "$CURRENT_STATE" > "$TMP_STATE" && mv -f "$TMP_STATE" "$STATE"
echo "🎉 IPv6地址已更新并记录: NEW=$NEW DHCPV6=$DHCPV6"
