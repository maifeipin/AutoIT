#!/bin/bash
# 系统监控脚本自动安装程序

# 检查并安装telnet
install_telnet() {
    if ! command -v telnet &> /dev/null; then
        echo "正在安装telnet客户端..."
        
        # 根据发行版安装
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
        
        # 验证安装
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

# 安装监控脚本
install_monitor() {
    echo "正在安装系统监控脚本..."
    sudo install -m 755 <(
        curl -sL https://raw.githubusercontent.com/maifeipin/AutoIT/main/system_monitor.sh | \
        sed "s|^MAILPIT_HOST=.*|MAILPIT_HOST=\"${MAILPIT_HOST:-mail.maifeipin.com}\"|;
             s|^SENDER_EMAIL=.*|SENDER_EMAIL=\"${SENDER_EMAIL:-sender@example.com}\"|;
             s|^RECEIVER_EMAIL=.*|RECEIVER_EMAIL=\"${RECEIVER_EMAIL:-receiver@maifeipin.com}\"|"
    ) /usr/local/bin/system_monitor
    
    # 创建服务文件
    sudo tee /etc/systemd/system/system-monitor.service > /dev/null <<EOF
[Unit]
Description=System Resource Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/system_monitor
Restart=always
RestartSec=30
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
}

# 主安装流程
echo "=== 系统监控脚本安装程序 ==="
install_telnet
install_monitor

# 启动服务
sudo systemctl enable --now system-monitor

# 验证安装
echo -e "\n安装结果验证："
echo -e "1. 服务状态："
sudo systemctl is-active system-monitor && \
    echo -e "\n2. 最近日志：" && \
    journalctl -u system-monitor -n 5 --no-pager

echo -e "\n安装完成！后续操作："
echo "查看完整日志：journalctl -u system-monitor -f"
echo "手动启动服务：sudo systemctl start system-monitor"
echo "配置修改后需重启：sudo systemctl restart system-monitor"
