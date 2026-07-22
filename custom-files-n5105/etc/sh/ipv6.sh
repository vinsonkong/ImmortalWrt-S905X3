#!/bin/bash

# ================= 配置项 =================
TITLE="n5105"
INTERFACE="br-lan"
STATE="/tmp/last_ipv6.txt"
WEB_PORT="39380"
PUSHPLUS_TOKEN="d3ab6649fb294bc8bd2bca56b58b6728"
SERVERCHAN_SENDKEY="SCT351115TJZf2hzUIS9gOckhLJ3SJAYbb"
# ==========================================

# 前置检查
command -v curl >/dev/null 2>&1 || { echo "❌ 错误: 未安装 curl"; exit 1; }
[[ "$PUSHPLUS_TOKEN" == "YOUR_"* ]] && PUSHPLUS_TOKEN=""
[[ "$SERVERCHAN_SENDKEY" == "YOUR_"* ]] && SERVERCHAN_SENDKEY=""

# ---------- 提取并验证 IPv6 地址 ----------
# 优先尝试 iproute2 标准输出格式
NEW=$(ip -6 addr show dev "$INTERFACE" scope global 2>/dev/null \
      | grep -oE 'inet6 [0-9a-fA-F:]+' \
      | awk '{print $2}' \
      | grep -viE '^fe80|^::1|^fd|^fc' \
      | head -n1)

# 备用提取方式（兼容部分旧版 ip 命令）
if [[ -z "$NEW" ]]; then
    NEW=$(ip -6 addr show dev "$INTERFACE" scope global 2>/dev/null \
          | grep -oE '[0-9a-fA-F:]{3,}/[0-9]+' \
          | cut -d'/' -f1 \
          | grep -viE '^fe80|^::1|^fd|^fc' \
          | head -n1)
fi

# 提取 DHCPv6-PD 地址（通常为 /128）
DHCPV6=$(ip -6 addr show dev "$INTERFACE" scope global 2>/dev/null \
         | grep -oE 'inet6 [0-9a-fA-F:]+' \
         | awk '{print $2}' \
         | grep -viE '^fe80|^::1|^fd|^fc' \
         | grep -v "$NEW" \
         | head -n1)

# ✅ 核心修正：如果没有检测到任何有效外网 IPv6，直接退出且不推送
if [[ -z "$NEW" && -z "$DHCPV6" ]]; then
    echo "⚠️ 未检测到有效的公网 IPv6 地址，跳过本次执行"
    # 如果之前有记录但现在没了，清除状态文件，确保下次恢复时能正常触发推送
    if [[ -f "$STATE" ]]; then
        rm -f "$STATE"
        echo "🗑️ 已清除旧的 IPv6 状态记录"
    fi
    exit 0
fi

# ---------- 检查地址是否发生变化 ----------
CURRENT_STATE="${NEW}|${DHCPV6}"
OLD_STATE=""
[[ -f "$STATE" ]] && OLD_STATE=$(cat "$STATE" 2>/dev/null)

if [[ "$CURRENT_STATE" == "$OLD_STATE" ]]; then
    echo "✅ IPv6 地址未变化，无需推送"
    echo "   SLAAC:  ${NEW:-无}"
    echo "   DHCPv6: ${DHCPV6:-无}"
    exit 0
fi

# 解析旧地址用于对比展示
OLD_NEW="${OLD_STATE%%|*}"
OLD_DHCP="${OLD_STATE##*|}"

echo "🔄 检测到 IPv6 地址变化:"
echo "   SLAAC:  ${OLD_NEW:-无} → ${NEW:-无}"
echo "   DHCPv6: ${OLD_DHCP:-无} → ${DHCPV6:-无}"

# ---------- 构建链接与时间 ----------
URL_NEW=""
URL_DHCPV6=""
[[ -n "$NEW" ]]     && URL_NEW="http://[${NEW}]:${WEB_PORT}"
[[ -n "$DHCPV6" ]]  && URL_DHCPV6="http://[${DHCPV6}]:${WEB_PORT}"
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
CURL_OPTS="-s --connect-timeout 5 --max-time 10"

# ---------- PushPlus 推送 ----------
if [[ -n "$PUSHPLUS_TOKEN" ]]; then
    PP_CONTENT="<b>📡 ${TITLE} IPv6 地址已更新</b><br/><br/>"
    [[ -n "$URL_NEW" ]]    && PP_CONTENT+="<b>前缀地址 (SLAAC):</b><br/><a href=\"${URL_NEW}\">${URL_NEW}</a><br/><br/>"
    [[ -n "$URL_DHCPV6" ]] && PP_CONTENT+="<b>PD地址 (DHCPv6):</b><br/><a href=\"${URL_DHCPV6}\">${URL_DHCPV6}</a><br/><br/>"
    PP_CONTENT+="<font color=\"gray\">更新时间: ${CURRENT_TIME}</font>"

    if command -v jq >/dev/null 2>&1; then
        JSON_PAYLOAD=$(jq -nc \
            --arg token "$PUSHPLUS_TOKEN" \
            --arg title "【IPv6更新】${TITLE}" \
            --arg content "$PP_CONTENT" \
            '{token:$token, title:$title, content:$content, template:"html"}')
    else
        # 无 jq 时的安全转义（处理换行、引号、反斜杠）
        ESCAPED_CONTENT=$(printf '%s' "$PP_CONTENT" \
            | sed ':a;N;$!ba;s/\n/\\n/g' \
            | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
        JSON_PAYLOAD="{\"token\":\"${PUSHPLUS_TOKEN}\",\"title\":\"【IPv6更新】${TITLE}\",\"content\":\"${ESCAPED_CONTENT}\",\"template\":\"html\"}"
    fi

    PP_RESULT=$(curl $CURL_OPTS -X POST "https://www.pushplus.plus/send" \
        -H "Content-Type: application/json" -d "$JSON_PAYLOAD" 2>&1)

    if echo "$PP_RESULT" | grep -q '"code":200'; then
        echo "✅ PushPlus 推送成功"
    else
        echo "❌ PushPlus 推送失败: $PP_RESULT"
    fi
fi

# ---------- ServerChan 推送 ----------
if [[ -n "$SERVERCHAN_SENDKEY" ]]; then
    SC_DESP="## 📡 ${TITLE} IPv6 地址已更新\n\n"
    [[ -n "$URL_NEW" ]]    && SC_DESP+="**(SLAAC地址):**[${URL_NEW}](${URL_NEW})"
    [[ -n "$URL_DHCPV6" ]] && SC_DESP+="**(DHCPv6地址):**[${URL_DHCPV6}](${URL_DHCPV6})"
    SC_DESP+="> 更新时间: ${CURRENT_TIME}"

    SC_RESULT=$(curl $CURL_OPTS -X POST "https://sctapi.ftqq.com/${SERVERCHAN_SENDKEY}.send" \
        --data-urlencode "title=【IPv6更新】${TITLE}" \
        --data-urlencode "desp=${SC_DESP}" 2>&1)

    if echo "$SC_RESULT" | grep -q '"code":0'; then
        echo "✅ ServerChan 推送成功"
    else
        echo "❌ ServerChan 推送失败: $SC_RESULT"
    fi
fi

# ---------- 保存新状态（原子写入）----------
TMP_STATE="${STATE}.tmp.$$"
echo "$CURRENT_STATE" > "$TMP_STATE" && mv -f "$TMP_STATE" "$STATE"
echo "🎉 IPv6 地址已更新并记录"
