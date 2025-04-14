#!/bin/bash
# 高精度系统监控脚本（严格格式控制版）

# 配置项
CPU_THRESHOLD=90
MEMORY_THRESHOLD=90
DISK_THRESHOLD=90
NETWORK_THRESHOLD=1
CHECK_INTERVAL=60
ALARM_COOL_DOWN=300

# 邮件和日志配置
MAILPIT_HOST="mail.maifeipin.com"
MAILPIT_PORT=1025
SENDER_EMAIL="sender@example.com"
RECEIVER_EMAIL="receiver@maifeipin.com"
LOG_FILE="/var/log/system_monitor.log"

# 初始化日志
exec >> "$LOG_FILE" 2>&1
echo "==== 监控脚本启动 $(date '+%F %T') ===="

# 获取CPU使用率（纳秒级精度）
get_cpu_usage() {
    local cpu_stats=($(grep '^cpu ' /proc/stat))
    local total=$(( ${cpu_stats[1]} + ${cpu_stats[2]} + ${cpu_stats[3]} + ${cpu_stats[4]} ))
    local idle=${cpu_stats[4]}
    
    if [[ -n $PREV_TOTAL ]]; then
        local diff_total=$((total - PREV_TOTAL))
        local diff_idle=$((idle - PREV_IDLE))
        echo $(( 100 * (diff_total - diff_idle) / diff_total ))
    fi
    
    PREV_TOTAL=$total
    PREV_IDLE=$idle
}

# 获取内存使用率（精确到KB）
get_mem_usage() {
    local mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    local mem_avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    echo $(( (mem_total - mem_avail) * 100 / mem_total ))
}

# 获取磁盘使用率（严格数字提取）
get_disk_usage() {
    df --output=pcent / | awk 'NR==2{gsub("%",""); print $1}'
}

# 网络检测（严格格式控制）
get_packet_loss() {
    local ping_output=$(ping -c 3 -W 2 qq.com 2>&1)
    if [[ $ping_output =~ ([0-9]+)%[[:space:]]+packet[[:space:]]+loss ]]; then
        loss="${BASH_REMATCH[1]}"
        if (( loss >= 0 && loss <= 100 )); then
            echo "$loss"
        else
            echo "100"  # 如果丢包率超出正常范围，视为完全丢包
        fi
    else
        echo "100"  # 当无法检测时视为完全丢包
    fi

}

# 邮件发送（强制UTF-8编码）
send_alert() {
    local subject="$1"
    local body="$2"
    
    {
        echo "EHLO $(hostname)"; sleep 0.3
        echo "MAIL FROM:<$SENDER_EMAIL>"; sleep 0.3
        echo "RCPT TO:<$RECEIVER_EMAIL>"; sleep 0.3
        echo "DATA"; sleep 0.3
        echo "From: <$SENDER_EMAIL>"
        echo "To: <$RECEIVER_EMAIL>"
        echo "Subject: =?UTF-8?B?$(echo -n "$subject" | base64)?="
        echo "Content-Type: text/plain; charset=UTF-8"
        echo "Content-Transfer-Encoding: base64"
        echo
        echo -e "$body" | base64
        echo "."
        sleep 0.3
        echo "QUIT"
    } | timeout 5 telnet "$MAILPIT_HOST" "$MAILPIT_PORT" >/dev/null 2>&1
}

# 主监控循环
trap 'echo "[$(date "+%F %T")] 安全退出"; exit 0' TERM INT
LAST_ALARM_TIME=0
PREV_TOTAL=
PREV_IDLE=

# 首次获取CPU基准
get_cpu_usage >/dev/null

while sleep $CHECK_INTERVAL; do
    TIMESTAMP=$(date "+%F %T")
    
    # 获取监控数据（带格式校验）
    CPU=$(get_cpu_usage)
    MEM=$(get_mem_usage)
    DISK=$(get_disk_usage)
    NET=$(get_packet_loss)
    
    # 严格格式化日志输出
    printf "%s CPU=%3d%% MEM=%3d%% DISK=%3d%% NET=%3d%%\n" \
        "$TIMESTAMP" "${CPU:-0}" "${MEM:-0}" "${DISK:-0}" "${NET:-100}"
    
    # 阈值检查（安全数值比较）
    ALERTS=()
    [[ $CPU =~ ^[0-9]+$ ]] && (( CPU > CPU_THRESHOLD )) && ALERTS+=("CPU:$CPU%")
    [[ $MEM =~ ^[0-9]+$ ]] && (( MEM > MEMORY_THRESHOLD )) && ALERTS+=("MEM:$MEM%")
    [[ $DISK =~ ^[0-9]+$ ]] && (( DISK > DISK_THRESHOLD )) && ALERTS+=("DISK:$DISK%")
    [[ $NET =~ ^[0-9]+$ ]] && (( NET > NETWORK_THRESHOLD )) && ALERTS+=("NET:$NET%")
    
    # 触发报警
    if (( ${#ALERTS[@]} > 0 )); then
        CURRENT_TIME=$(date +%s)
        if (( CURRENT_TIME - LAST_ALARM_TIME >= ALARM_COOL_DOWN )); then
            SUBJECT="【报警】$(hostname)-${ALERTS[*]}"
            
            BODY="▌ 异常指标\n"
            BODY+=$(printf "%-12s: %3d%% (阈值: %3d%%)\n" \
                    "CPU使用率" "$CPU" "$CPU_THRESHOLD" \
                    "内存使用率" "$MEM" "$MEMORY_THRESHOLD" \
                    "磁盘使用率" "$DISK" "$DISK_THRESHOLD" \
                    "网络丢包率" "$NET" "$NETWORK_THRESHOLD")
            
            BODY+="\n▌ 系统状态\n"
            BODY+="主机名  : $(hostname)\n"
            BODY+="检测时间: $TIMESTAMP\n"
            BODY+="运行时间: $(uptime -p)\n"
            
            if send_alert "$SUBJECT" "$BODY"; then
                LAST_ALARM_TIME=$CURRENT_TIME
                echo "$TIMESTAMP 报警已发送: ${ALERTS[*]}"
            else
                echo "$TIMESTAMP 邮件发送失败"
            fi
        fi
    fi
done
