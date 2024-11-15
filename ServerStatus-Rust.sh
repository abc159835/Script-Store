#!/bin/bash

set -ex
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH


apt-get install -y curl unzip vnstat

# get_architecture
arch=$(uname -m)

# 设置 ARCHITECTURE 变量
if [[ $arch == "aarch64" ]]; then
    ARCHITECTURE="aarch64"
elif [[ $arch == "x86_64" ]]; then
    ARCHITECTURE="x86_64"
else
    ARCHITECTURE="unknown"
fi


OS_ARCH=$ARCHITECTURE
server_address=${1}         # rust_serverstatus 服务端网址
WORKDIR=${2}                # 安装目录
ssr_uid=${3}                # rust_serverstatus 配置文件里的用户名
passwd=${4}                 # rust_serverstatus 配置文件里用户名对应的密码
install_server_or_not=${5}  # 空着就不安装服务端

mkdir -p ${WORKDIR}
cd ${WORKDIR}

github_project="zdz/ServerStatus-Rust"
tag=$(curl -m 10 -sL "https://api.github.com/repos/$github_project/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')


# step 1: 下载和解压客户端
curl -L -O https://github.com/zdz/ServerStatus-Rust/releases/download/${tag}/client-${OS_ARCH}-unknown-linux-musl.zip
unzip -o "client-${OS_ARCH}-unknown-linux-musl.zip"
rm "client-${OS_ARCH}-unknown-linux-musl.zip"

# client systemd service
cat > /etc/systemd/system/stat_client.service <<EOF
[Unit]
Description=ServerStatus-Rust Client
After=network.target

[Service]
WorkingDirectory=${WORKDIR}
ExecStart=${WORKDIR}/stat_client -a "${server_address}" -u ${ssr_uid} -p ${passwd} -n
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 判断是否部署服务端，不部署就直接退出
if [[ -z ${install_server_or_not} ]]; then
    exit 1
fi

# 下载和解压服务端
curl -L -O https://github.com/zdz/ServerStatus-Rust/releases/download/${tag}/server-${OS_ARCH}-unknown-linux-musl.zip
unzip -o "server-${OS_ARCH}-unknown-linux-musl.zip"
rm "server-${OS_ARCH}-unknown-linux-musl.zip"

# server systemd service
cat > /etc/systemd/system/stat_server.service <<EOF
# /etc/systemd/system/stat_server.service
[Unit]
Description=ServerStatus-Rust Server
After=network.target

[Service]
WorkingDirectory=${WORKDIR}
ExecStart=${WORKDIR}/stat_server -c ${WORKDIR}/config.toml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload
systemctl enable --now stat_server
systemctl status stat_server