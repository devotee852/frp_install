#!/bin/bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：必须使用root权限运行此脚本！" >&2
    exit 1
fi

# 识别系统类型
if grep -qi "debian" /etc/os-release; then
    PKG_MANAGER="apt-get"
elif grep -qi "centos" /etc/os-release; then
    PKG_MANAGER="yum"
else
    echo "错误：不支持的系统！仅支持Debian/CentOS" >&2
    exit 1
fi

# 安装依赖
$PKG_MANAGER update -y
$PKG_MANAGER install -y wget tar

# 下载Frp
FRP_VERSION="0.43.0"
FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz"
wget -O /tmp/frp.tar.gz "$FRP_URL"

# 创建目录
mkdir -p /etc/frp /var/log/frp /usr/local/frp

# 解压文件
tar -zxvf /tmp/frp.tar.gz -C /usr/local/frp --strip-components=1

# 复制二进制文件
cp /usr/local/frp/frps /usr/local/bin/
chmod +x /usr/local/bin/frps

# 创建配置文件模板
cat > /etc/frp/frps.ini << EOF
[common]
bind_port = 7000
token = your_token_here

dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin

log_file = /var/log/frp/frps.log
log_level = info
log_max_days = 3
EOF

# 创建systemd服务
cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=Frp Server Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.ini
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 创建管理脚本
cat > /usr/local/bin/frp << 'EOF'
#!/bin/bash

SERVICE_NAME="frps"

if [ "$1" = "1" ]; then
    echo "重载服务配置..."
    systemctl daemon-reload
    systemctl restart $SERVICE_NAME
elif [ "$1" = "2" ]; then
    systemctl start $SERVICE_NAME
elif [ "$1" = "3" ]; then
    systemctl stop $SERVICE_NAME
elif [ "$1" = "4" ]; then
    systemctl restart $SERVICE_NAME
elif [ "$1" = "5" ]; then
    systemctl status $SERVICE_NAME
else
    echo "请选择操作："
    echo "1. 重载服务配置并重启"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 查看服务状态"
    read -p "输入数字 (1-5): " num
    exec /usr/local/bin/frp "$num"
fi
EOF

# 设置权限
chmod +x /usr/local/bin/frp

# 重载systemd
systemctl daemon-reload
systemctl enable frps

echo "----------------------------------------"
echo "Frps 安装完成！"
echo "管理命令: frp [选项]"
echo "配置文件: /etc/frp/frps.ini"
echo "日志文件: /var/log/frp/frps.log"
echo "----------------------------------------"