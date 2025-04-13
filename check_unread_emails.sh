#!/bin/bash
# 邮件处理脚本（带主题去重和状态标记）

# API配置
MAIL_API="https://mail.maifeipin.com/api/v1"
SEND_MESSAGE_API="http://127.0.0.1:1234/send_message"
API_TOKEN="_token"
MAIL_AUTH="user:pasword"

# 日志配置
LOG_FILE="/var/log/mail_processor.log"
MAX_LOG_SIZE=1048576  # 1MB后轮转

# 初始化日志
setup_logging() {
    touch "$LOG_FILE"
    # 日志轮转
    if [ $(stat -c %s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
    fi
    exec >> "$LOG_FILE" 2>&1
}

# 获取当前时间戳
timestamp() {
    date '+%Y-%m-%d %T'
}

# 发送消息到目标API
send_message() {
    local subject="$1"
    local content="$2"
    
    curl -s -X POST "$SEND_MESSAGE_API" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg subj "$subject" --arg cont "$content" '{
            "message": ("Subject: " + $subj + "\nContent: " + $cont)
        }')"
}

# 标记邮件为已读
mark_as_read() {
    local ids=("$@")
    local ids_json=$(printf '%s\n' "${ids[@]}" | jq -R . | jq -s .)
    
    curl -s -X PUT "$MAIL_API/messages" \
        -H 'accept: application/json' \
        -H 'content-type: application/json' \
        -u "$MAIL_AUTH" \
        -d "{\"IDs\": $ids_json, \"Read\": true}"
}

# 主处理流程
process_emails() {
    echo "$(timestamp) === 开始处理邮件 ==="
    
    # 使用关联数组存储已处理主题
    declare -A processed_subjects
    declare -a successful_ids
    
    # 获取未读邮件
    emails=$(curl -s -X GET "$MAIL_API/messages" \
        -H 'accept: application/json' \
        -u "$MAIL_AUTH" | \
        jq -c '.messages[] | select(.Read == false)')
    
    while read -r email; do
        id=$(jq -r '.ID' <<< "$email")
        subject=$(jq -r '.Subject' <<< "$email")
        content=$(jq -r '.Snippet' <<< "$email")
        
        # 主题去重检查
        if [[ -n "${processed_subjects[$subject]}" ]]; then
            echo "$(timestamp) [跳过] 重复主题: $subject (ID: $id)"
            successful_ids+=("$id")  # 即使跳过，也将其ID添加到已读列表
            continue
        fi
        
        echo "$(timestamp) [处理] 邮件ID: $id | 主题: $subject"
        
        # 发送消息
        response=$(send_message "$subject" "$content")
        errcode=$(jq -r '.errcode' <<< "$response")
        
        if [[ "$errcode" -eq 0 ]]; then
            echo "$(timestamp) [成功] 已发送主题: $subject"
            successful_ids+=("$id")
            processed_subjects["$subject"]=1
        else
            errmsg=$(jq -r '.errmsg' <<< "$response")
            echo "$(timestamp) [失败] 主题: $subject | 错误: $errmsg"
        fi
    done <<< "$emails"
    
    # 批量标记已读
    if [[ ${#successful_ids[@]} -gt 0 ]]; then
        echo "$(timestamp) [状态] 正在标记 ${#successful_ids[@]} 封邮件为已读..."
        mark_result=$(mark_as_read "${successful_ids[@]}")
        
        if [[ $? -eq 0 ]]; then
            echo "$(timestamp) [成功] 邮件标记完成"
        else
            echo "$(timestamp) [失败] 标记错误: $mark_result"
        fi
    else
        echo "$(timestamp) [信息] 没有需要标记的邮件"
    fi
    
    echo "$(timestamp) === 处理完成 ==="
}

# 主执行流程
main() {
    setup_logging
    process_emails
    exit 0
}

main
