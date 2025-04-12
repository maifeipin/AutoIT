#!/usr/bin/env python3
import smtplib
import socket
import subprocess
import json
from datetime import datetime, timedelta
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def get_active_interface():
    try:
        # 获取活动的网络接口，排除回环接口
        result = subprocess.getoutput("ip -o link show | awk -F': ' '{print $2}' | grep -v lo")
        interfaces = result.split("\n")
        if interfaces:
            return interfaces[0]  # 返回第一个非回环接口
        else:
            return None
    except:
        return None

def get_public_ip():
    try:
        # 获取 IPv4 地址
        ipv4 = subprocess.getoutput("curl -s4 ifconfig.me")
        # 获取 IPv6 地址
        ipv6 = subprocess.getoutput("curl -s6 ifconfig.me")
        # 如果 IPv4 为空，则返回 "无公网 IPV4"
        if not ipv4:
            ipv4 = "无公网 IPV4"
        
        # 如果 IPv6 为空，则返回 "无公网 IPV6"
        if not ipv6:
            ipv6 = "无公网 IPV6"
        
        return f"IPV4: {ipv4} IPV6: {ipv6}"
    except Exception as e:
        return f"无法获取公网IP: {str(e)}"


def get_traffic_stats(interface):
    try:
        # 获取指定接口的JSON格式流量数据，限制7天
        result = subprocess.getoutput(f"vnstat --json d -i {interface} --limit 7")
        data = json.loads(result)

        # 获取当天日期
        today = datetime.now().strftime("%Y-%m-%d")

        # 查找当天的流量数据
        today_total = 0
        traffic_days = []

        for iface in data.get('interfaces', []):
            if iface.get('name') != interface:
                continue

            for day in iface.get('traffic', {}).get('day', []):
                date_str = f"{day['date']['year']}-{day['date']['month']:02d}-{day['date']['day']:02d}"
                rx = day.get('rx', 0)
                tx = day.get('tx', 0)
                total = rx + tx

                # 如果是当天，记录总流量
                if date_str == today:
                    today_total = total

                # 记录最近7天数据
                traffic_days.append({
                    'date': date_str,
                    'rx': rx,
                    'tx': tx,
                    'total': total
                })

        # 获取原始表格输出（指定接口，7天）
        raw_output = subprocess.getoutput(f"vnstat -d -i {interface} --limit 7")

        return {
            'today_total': today_total,
            'traffic_days': traffic_days,
            'raw': raw_output,
            'error': None
        }
    except Exception as e:
        return {
            'error': f'获取流量统计失败: {str(e)}',
            'today_total': 0,
            'traffic_days': [],
            'raw': ''
        }

def format_bytes(size):
    # 将字节数转换为更友好的格式
    power = 2**10
    n = 0
    units = {0: 'B', 1: 'KiB', 2: 'MiB', 3: 'GiB', 4: 'TiB'}
    while size > power and n < len(units)-1:
        size /= power
        n += 1
    return f"{size:.2f} {units[n]}"

def generate_traffic_table(traffic_days):
    # 生成格式化的流量表格
    table = "日期        接收(RX)    发送(TX)    总计\n"
    table += "--------------------------------------------\n"

    for day in sorted(traffic_days, key=lambda x: x['date'], reverse=True):
        table += f"{day['date']}  {format_bytes(day['rx']):>10}  {format_bytes(day['tx']):>10}  {format_bytes(day['total']):>10}\n"

    return table

def get_disk_space():
    # 获取磁盘剩余空间
    result = subprocess.getoutput("df -h / | awk 'NR==2 {print $4}'")
    return result

def send_email(traffic_data, interface):
    # 配置 SMTP 服务器
    smtp_server = 'mail.maifeipin.com'
    smtp_port = 1025

    # 发件人和收件人
    sender_email = 'root@local.host'
    receiver_email = 'autoit@maifeipin.com'

    # 获取主机信息
    hostname = socket.gethostname()
    public_ip = get_public_ip()

    # 获取磁盘空间
    disk_space = get_disk_space()

    # 准备邮件内容
    if traffic_data['error']:
        subject = f"{hostname} ({public_ip}) 流量报告错误"
        body = f"""
主机名: {hostname}
公网IP: {public_ip}
接口: {interface}

错误信息:
{traffic_data['error']}

磁盘剩余空间: {disk_space}
"""
    else:
        today_total = format_bytes(traffic_data['today_total'])
        traffic_table = generate_traffic_table(traffic_data['traffic_days'])

        subject = f"{hostname} ({public_ip}) {interface} 今日流量: {today_total}"
        body = f"""
主机名: {hostname}
公网IP: {public_ip}
接口: {interface}
今日总流量: {today_total}

最近7天流量统计:
{traffic_table}

原始vnstat输出:
{traffic_data['raw']}

磁盘剩余空间: {disk_space}
"""

    # 创建 MIME 对象
    msg = MIMEMultipart()
    msg['From'] = sender_email
    msg['To'] = receiver_email
    msg['Subject'] = subject
    msg.attach(MIMEText(body, 'plain'))

    try:
        server = smtplib.SMTP(smtp_server, smtp_port)
        server.sendmail(sender_email, receiver_email, msg.as_string())
        print("邮件发送成功")
    except Exception as e:
        print(f"邮件发送失败: {str(e)}")
    finally:
        server.quit()

if __name__ == "__main__":
    # 获取活动网络接口
    interface = get_active_interface()
    if interface:
        print(f"使用网络接口: {interface}")
        traffic_data = get_traffic_stats(interface)
        send_email(traffic_data, interface)
    else:
        print("未找到有效的网络接口！")
