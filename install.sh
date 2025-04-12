#!/bin/bash

# 配置变量
SCRIPT_REPO_URL="https://github.com/maifeipin/AutoIT.git"
SCRIPT_DIR="/root/script"
EMAIL_SCRIPT="send_daily_report.py"
CRON_SCHEDULE="0 23 * * * /usr/bin/python3 ${SCRIPT_DIR}/${EMAIL_SCRIPT} >> /var/log/traffic_report.log 2>&1"
CRON_FILE="/var/spool/cron/crontabs/root"
TMP_DIR="/tmp"
TMP_SCRIPT_PATH="${TMP_DIR}/${EMAIL_SCRIPT}"

# 1. 克隆或更新脚本仓库
if [ ! -d "${SCRIPT_DIR}" ]; then
    echo "脚本目录不存在，正在克隆仓库..."
    git clone "${SCRIPT_REPO_URL}" "${SCRIPT_DIR}"
else
    echo "脚本目录已存在，正在拉取最新代码..."
    cd "${SCRIPT_DIR}"
    git pull origin main
fi

# 2. 删除旧的脚本文件并从 GitHub 下载最新脚本
echo "正在删除旧的 Python 脚本并从 GitHub 下载新的脚本..."
rm -f "${SCRIPT_DIR}/${EMAIL_SCRIPT}"
curl -s -o "${TMP_SCRIPT_PATH}" "https://raw.githubusercontent.com/maifeipin/AutoIT/main/${EMAIL_SCRIPT}"

# 3. 移动下载的脚本到目标目录
mv -f "${TMP_SCRIPT_PATH}" "${SCRIPT_DIR}/${EMAIL_SCRIPT}"

# 4. 检查并设置定时任务
echo "正在检查和设置定时任务..."
CRON_EXIST=$(grep -F "${EMAIL_SCRIPT}" "${CRON_FILE}")

if [ -z "${CRON_EXIST}" ]; then
    # 如果没有找到相同的定时任务，则添加
    echo "没有找到现有的定时任务，正在添加新的定时任务..."
    echo "${CRON_SCHEDULE}" >> "${CRON_FILE}"
else
    # 如果找到了相同的定时任务，则先删除旧的定时任务
    echo "找到现有的定时任务，正在删除..."
    sed -i "/${EMAIL_SCRIPT}/d" "${CRON_FILE}"
    echo "删除完成，重新添加定时任务..."
    echo "${CRON_SCHEDULE}" >> "${CRON_FILE}"
fi

# 5. 检查 Python3 路径
if ! command -v python3 &> /dev/null; then
    echo "错误: 未找到 Python3，请确保 Python3 已安装并在 PATH 中。"
    exit 1
fi

# 6. 检查磁盘空间
echo "正在检查磁盘剩余空间..."
DISK_SPACE=$(df -h | grep '/$' | awk '{print $4}')  # 获取根目录剩余空间

# 7. 获取当前日期和时间
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# 8. 发送磁盘空间信息到邮件中
echo "磁盘剩余空间: ${DISK_SPACE}"

# 9. 重启 cron 服务以应用新的定时任务
echo "重启 cron 服务以应用新的定时任务..."
systemctl restart cron

echo "脚本已成功更新并配置！"
