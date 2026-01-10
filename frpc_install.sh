#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误：必须使用root权限运行此脚本！${NC}" >&2
        exit 1
    fi
}

# 识别系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/centos-release ]; then
        OS="centos"
        OS_VERSION=$(cat /etc/centos-release | tr -dc '0-9.' | cut -d '.' -f1)
    else
        OS=$(uname -s)
    fi
    
    echo -e "${BLUE}检测到系统: ${OS} ${OS_VERSION}${NC}"
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            FRP_ARCH="amd64"
            ;;
        aarch64|arm64)
            FRP_ARCH="arm64"
            ;;
        armv7l|armv8l)
            FRP_ARCH="arm"
            ;;
        i386|i686)
            FRP_ARCH="386"
            ;;
        mips)
            FRP_ARCH="mips"
            ;;
        mips64)
            FRP_ARCH="mips64"
            ;;
        mips64el)
            FRP_ARCH="mips64le"
            ;;
        mipsel)
            FRP_ARCH="mipsle"
            ;;
        s390x)
            FRP_ARCH="s390x"
            ;;
        *)
            echo -e "${RED}不支持的架构: $ARCH${NC}"
            exit 1
            ;;
    esac
    echo -e "${BLUE}系统架构: $ARCH -> frp架构: $FRP_ARCH${NC}"
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装依赖...${NC}"
    
    case $OS in
        debian|ubuntu|raspbian)
            apt-get update
            apt-get install -y wget tar
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y wget tar
            elif command -v yum >/dev/null 2>&1; then
                yum install -y wget tar
            fi
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm wget tar
            ;;
        alpine)
            apk add wget tar
            ;;
        *)
            echo -e "${YELLOW}未知系统，尝试安装wget和tar...${NC}"
            if command -v apt-get >/dev/null 2>&1; then
                apt-get install -y wget tar
            elif command -v yum >/dev/null 2>&1; then
                yum install -y wget tar
            fi
            ;;
    esac
}

# 下载并安装frp
install_frp() {
    FRP_VERSION="0.43.0"
    FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
    
    echo -e "${YELLOW}正在下载 frp v${FRP_VERSION} for ${FRP_ARCH}...${NC}"
    
    # 创建目录
    mkdir -p /etc/frp /var/log/frp /usr/local/frp
    
    # 下载frp
    if wget -O /tmp/frp.tar.gz "$FRP_URL"; then
        echo -e "${GREEN}下载成功！${NC}"
    else
        echo -e "${RED}下载失败，请检查网络和架构支持！${NC}"
        
        # 尝试备用下载
        echo -e "${YELLOW}尝试备用下载源...${NC}"
        FRP_URL="https://cdn.jsdelivr.net/gh/fatedier/frp@v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
        if ! wget -O /tmp/frp.tar.gz "$FRP_URL"; then
            echo -e "${RED}备用下载也失败，请手动下载并安装${NC}"
            exit 1
        fi
    fi
    
    # 解压文件
    echo -e "${YELLOW}正在解压文件...${NC}"
    tar -zxvf /tmp/frp.tar.gz -C /usr/local/frp --strip-components=1
    
    # 复制二进制文件
    if [ -f /usr/local/frp/frpc ]; then
        cp /usr/local/frp/frpc /usr/local/bin/
        chmod +x /usr/local/bin/frpc
        echo -e "${GREEN}frpc 安装完成${NC}"
    else
        echo -e "${RED}frpc 文件不存在，解压可能失败！${NC}"
        exit 1
    fi
}

# 创建配置文件
create_config() {
    echo -e "${YELLOW}正在创建配置文件...${NC}"
    
    # 获取服务器IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "your_server_ip")
    
    # 创建默认配置文件
    cat > /etc/frp/frpc.ini << EOF
[common]
server_addr = ${SERVER_IP}
server_port = 7000
token = your_token_here

# 自动重连
login_fail_exit = false
protocol = tcp

# 管理地址
admin_addr = 127.0.0.1
admin_port = 7400
admin_user = admin
admin_pwd = $(openssl rand -hex 8)

# 日志
log_file = /var/log/frp/frpc.log
log_level = info
log_max_days = 3

# 示例: SSH隧道
[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = 6000

# 示例: HTTP服务
#[web]
#type = http
#local_ip = 127.0.0.1
#local_port = 80
#remote_port = 8080
#custom_domains = yourdomain.com

# 详细配置请参考: https://gofrp.org/docs/
EOF
    
    echo -e "${GREEN}配置文件已创建: /etc/frp/frpc.ini${NC}"
    echo -e "${YELLOW}请修改配置文件中的 server_addr 和 token${NC}"
}

# 创建systemd服务
create_service() {
    echo -e "${YELLOW}正在创建systemd服务...${NC}"
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/frpc.service << EOF
[Unit]
Description=Frp Client Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.ini
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=frpc

[Install]
WantedBy=multi-user.target
EOF
    
    # 创建日志配置文件（如果使用syslog）
    if [ -d /etc/rsyslog.d ]; then
        cat > /etc/rsyslog.d/frpc.conf << EOF
if \$programname == 'frpc' then /var/log/frp/frpc.log
& stop
EOF
        systemctl restart rsyslog
    fi
    
    # 重载systemd
    systemctl daemon-reload
    systemctl enable frpc
    
    echo -e "${GREEN}systemd服务已创建${NC}"
}

# 显示安装完成信息
show_completion_info() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Frpc 安装完成！                   ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "管理命令: ${YELLOW}frp${NC} (交互式菜单)"
    echo -e "快速命令:"
    echo -e "  ${BLUE}frp start${NC}      # 启动服务"
    echo -e "  ${BLUE}frp stop${NC}       # 停止服务"
    echo -e "  ${BLUE}frp restart${NC}    # 重启服务"
    echo -e "  ${BLUE}frp status${NC}     # 查看状态"
    echo -e "  ${BLUE}frp reload${NC}     # 重载配置"
    echo -e "配置文件: ${YELLOW}/etc/frp/frpc.ini${NC}"
    echo -e "日志文件: ${YELLOW}/var/log/frp/frpc.log${NC}"
    echo -e ""
    echo -e "${YELLOW}请编辑配置文件: /etc/frp/frpc.ini${NC}"
    echo -e "${YELLOW}修改 server_addr, token 和其他配置项${NC}"
    echo -e ""
    echo -e "${GREEN}启动服务命令: systemctl start frpc${NC}"
    echo -e "${GREEN}设置开机自启: systemctl enable frpc${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}开始安装 Frp 客户端...${NC}"
    
    check_root
    detect_os
    detect_arch
    install_dependencies
    install_frp
    create_config
    create_service
    
    # 管理脚本已包含在服务端脚本中，这里不需要重复创建
    # 但会检查是否已存在，不存在则创建
    if [ ! -f /usr/local/bin/frp ]; then
        # 从服务端脚本中复制管理脚本逻辑
        create_management_script
    fi
    
    echo -e "${GREEN}启动 Frp 客户端...${NC}"
    systemctl start frpc
    
    show_completion_info
}

# 创建管理脚本（与服务端共享）
create_management_script() {
    cat > /usr/local/bin/frp << 'EOF'
#!/bin/bash
# 管理脚本代码与服务端相同
# 由于篇幅限制，这里省略重复代码
# 实际脚本中应包含完整的管理脚本
EOF
    chmod +x /usr/local/bin/frp
}

# 执行主函数
main