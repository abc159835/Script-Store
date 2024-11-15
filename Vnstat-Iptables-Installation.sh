#!/bin/bash

set -e

# 安装必要的依赖
apt-get install -y vnstat iptables

# 创建 vnstat_iptables.sh 脚本
cat > /opt/vnstat_iptables.sh <<'EOF'
#!/bin/bash

# 目标限制：每月 tx 超过 90 GiB
LIMIT=90
PORT=2200
VNSTAT_ALERT_CMD="vnstat --alert 3 3 m tx $LIMIT GiB"

# 重置 iptables 规则的函数
reset_iptables() {
    iptables -D INPUT -p tcp --dport $PORT -j DROP 2>/dev/null
    echo "Reset iptables rules for port $PORT"
}

# 添加阻断规则的函数
block_port() {
    iptables -C INPUT -p tcp --dport $PORT -j DROP 2>/dev/null || iptables -A INPUT -p tcp --dport $PORT -j DROP
    echo "Blocked rx on port $PORT"
}

# 检查日期，若为月初则重置 iptables
check_and_reset_monthly() {
    if [[ $(date +%d) -eq 1 ]]; then
        reset_iptables
    fi
}

# 主循环，定期检查流量
while true; do
    # 每月检查重置规则
    check_and_reset_monthly

    # 执行 vnstat 命令
    $VNSTAT_ALERT_CMD
    STATUS=$?

    # 判断流量是否超出，只有超出时才记录日志
    if [[ $STATUS -eq 1 ]]; then
        echo "$(date) - Monthly tx exceeds ${LIMIT}GB. Blocking port $PORT." >> /var/log/vnstat_iptables.log
        block_port
    fi

    # 等待 100 秒后继续循环
    sleep 100
done
EOF

# 给脚本文件赋予执行权限
chmod +x /opt/vnstat_iptables.sh

# 创建 systemd 服务文件
cat > /etc/systemd/system/vnstat_iptables.service <<EOF
[Unit]
Description=VNStat Traffic Monitor and Iptables Blocker
After=network.target

[Service]
ExecStart=/bin/bash /opt/vnstat_iptables.sh
Restart=always
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload
systemctl enable --now vnstat_iptables.service
systemctl status vnstat_iptables.service