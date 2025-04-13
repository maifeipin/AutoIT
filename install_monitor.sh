#!/bin/bash
# 修复版系统监控安装脚本

# 配置项（用户可以根据需要修改）
MAILPIT_HOST="mail.maifeipin.com"
SENDER_EMAIL="sender@example.com"
RECEIVER_EMAIL="receiver@maifeipin.com"

# 检查并安装telnet
install_telnet() {
    if ! command -v telnet &> /dev/null; then
        echo "正在安装telnet客户端..."
        
        if [[ -f /etc/debian_version ]]; then
            sudo apt-get update -qq
            sudo apt-get install -y telnet
        elif [[ -f /etc/redhat-release ]]; then
            sudo yum install -y telnet
        elif [[ -f /etc/alpine-release ]]; then
            sudo apk add busybox-extras
        else
            echo "无法自动安装telnet：未知的Linux发行版"
            exit 1
        fi
        
        if ! command -v telnet &> /dev/null; then
            echo "telnet安装失败！请手动安装后重试"
            exit 1
        else
            echo "telnet安装成功：$(which telnet)"
        fi
    else
        echo "telnet已安装：$(which telnet)"
    fi
}

# 安装监控脚本（修复文件创建问题）
install_monitor() {
    echo "正在下载并安装监控脚本..."
    
    # 创建临时目录并检查
    TMP_DIR=$(mktemp -d)
    if [[ ! -d "$TMP_DIR" ]]; then
        echo "无法创建临时目录！"
        exit 1
    fi

    TMP_SCRIPT="${TMP_DIR}/system_monitor.sh"
    
    # 下载脚本
    curl -sL https://raw.githubusercontent.com/maifeipin/AutoIT/main/system_monitor.sh -o "$TMP_SCRIPT"
    
    if [[ ! -f "$TMP_SCRIPT" ]]; then
        echo "下载监控脚本失败，脚本未找到！"
        exit 1
    fi
    
    # 替换配置参数
    sed -i \
        -e "s|^MAILPIT_HOST=.*|MAILPIT_HOST=\"${MAILPIT_HOST:-mail.maifeipin.com}\"|" \
        -e "s|^SENDER_EMAIL=.*|SENDER_EMAIL=\"${SENDER_EMAIL:-sender@example.com}\"|" \
        -e "s|^RECEIVER_EMAIL=.*|RECEIVER_EMAIL=\"${RECEIVER_EMAIL:-receiver@maifeipin.com}\"|" \
        "$TMP_SCRIPT"
    
    # 安装脚本到指定目录
    sudo install -m 755 "$TMP_SCRIPT" /usr/local/bin/system_monitor
    if [[ $? -ne 0 ]]; then
        echo "安装监控脚本失败！"
        exit 1
    fi
    
    rm -f "$TMP_SCRIPT"
    
    # 创建服务文件
    sudo tee /etc/systemd/system/system-monitor.service > /dev/null <<EOF
[Unit]
Description=System Resource Monitor
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
ExecStart=/usr/local/bin/system_monitor
Restart=always
RestartSec=30
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd 配置
    sudo systemctl daemon-reload
}

# 启动服务（增加状态检查）
start_service() {
    echo -e "\n启动监控服务..."
    sudo systemctl enable --now system-monitor
    
    # 等待服务启动
    for i in {1..5}; do
        if systemctl is-active system-monitor &>/dev/null; then
            echo "服务启动成功！"
            return 0
        fi
        sleep 1
    done
    
    echo "服务启动失败，请检查："
    journalctl -u system-monitor -n 10 --no-pager
    exit 1
}

# 主安装流程
echo "=== 系统监控脚本安装程序 ==="
install_telnet
install_monitor

start_service

# 验证安装
echo -e "\n安装验证："
echo -e "1. 服务状态：$(systemctl is-active system-monitor)"
echo -e "2. 脚本路径：$(ls -lh /usr/local/bin/system_monitor)"
echo -e "3. 最近日志："
journalctl -u system-monitor -n 5 --no-pager | grep -v "Started\|Starting"

echo -e "\n安装完成！使用以下命令查看实时日志："
echo "journalctl -u system-monitor -f"
