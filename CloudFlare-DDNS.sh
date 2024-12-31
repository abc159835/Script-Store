#!/bin/bash

set -e
apt-get install -y curl

cat > /opt/cf_ddns.sh <<'EOF'
#!/bin/bash

set -e

# Cloudflare API 和域名配置
CFKEY=""
CFZONE_NAME=""
CFRECORD_NAME=""
CFRECORD_TYPE="A"
CFTTL=60
FORCE=false

WANIPSITE="http://ipv4.icanhazip.com"

# 检查命令行参数
while getopts k:h:z:t:f: opts; do
    case ${opts} in
        k) CFKEY=${OPTARG} ;;
        h) CFRECORD_NAME=${OPTARG} ;;
        z) CFZONE_NAME=${OPTARG} ;;
        t) CFRECORD_TYPE=${OPTARG} ;;
        f) FORCE=${OPTARG} ;;
    esac
done

# 如果缺少必需的设置则退出
if [ -z "$CFKEY" ]; then
    echo "缺少 API 密钥，获取地址: https://www.cloudflare.com/a/account/my-account"
    exit 2
fi
if [ -z "$CFRECORD_NAME" ]; then
    echo "缺少主机名，需更新的域名是什么？"
    exit 2
fi

# 获取 Cloudflare Zone ID 和 DNS 记录 ID
CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" -H "Authorization: Bearer $CFKEY" -H "Content-Type: application/json" | grep -Eo '"id":"[^"]*' | sed 's/"id":"//' | head -1)
CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" -H "Authorization: Bearer $CFKEY" -H "Content-Type: application/json" | grep -Eo '"id":"[^"]*' | sed 's/"id":"//' | head -1)

# 监控循环，定期检查 IP
while true; do
    # 获取当前外部 IP 地址
    WAN_IP=$(curl -s ${WANIPSITE})

    # 检查是否需要更新
    if [ -f $HOME/.cf-wan_ip_$CFRECORD_NAME ]; then
        OLD_WAN_IP=$(cat $HOME/.cf-wan_ip_$CFRECORD_NAME)
    else
        OLD_WAN_IP=""
    fi

    # 如果 IP 未变且没有强制更新，跳过
    if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = false ]; then
        sleep 60
        continue
    fi

    # 更新 Cloudflare DNS 记录
    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
        -H "Authorization: Bearer $CFKEY" \
        -H "Content-Type: application/json" \
        --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\", \"ttl\":$CFTTL}")

    # 如果更新成功，输出并保存新 IP
    if [[ "$RESPONSE" == *"\"success\":true"* ]]; then
        echo "$(date) - IP 更新为 $WAN_IP"
        echo $WAN_IP > $HOME/.cf-wan_ip_$CFRECORD_NAME
    fi

    # 每 60 秒检查一次
    sleep 60
done
EOF

chmod +x /opt/cf_ddns.sh

# 创建 systemd 服务文件
cat > /etc/systemd/system/cf_ddns.service <<EOF
[Unit]
Description=Cloudflare Dynamic DNS Update Service
After=network.target

[Service]
ExecStart=/bin/bash /opt/cf_ddns.sh -k ${1} -h ${2} -z ${3}
Restart=always
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cf_ddns.service
systemctl status cf_ddns.service
