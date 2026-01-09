#!/bin/bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 此脚本需要root权限运行" >&2
    exit 1
fi

# 常量定义
FRP_URL="https://github.com/fatedier/frp/releases/download/v0.43.0/frp_0.43.0_linux_amd64.tar.gz"
INSTALL_DIR="/usr/local/frp"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/frp"
SERVICE_NAME="frps"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
MANAGER_FILE="/usr/local/bin/frp_manager"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示带颜色的消息
show_message() {
    case $1 in
        success) echo -e "${GREEN}$2${NC}";;
        error) echo -e "${RED}$2${NC}";;
        warning) echo -e "${YELLOW}$2${NC}";;
        info) echo -e "${BLUE}$2${NC}";;
    esac
}

# 安装Frps服务
install_frps() {
    echo "正在安装Frp Server..."
    
    # 创建目录
    mkdir -p $INSTALL_DIR $CONFIG_DIR
    
    # 下载文件
    show_message info "正在下载FRP..."
    wget -qO /tmp/frp.tar.gz $FRP_URL || {
        show_message error "下载失败"
        exit 1
    }
    
    # 解压文件
    show_message info "正在解压文件..."
    tar -xzf /tmp/frp.tar.gz -C $INSTALL_DIR --strip-components=1
    
    # 复制二进制文件
    cp $INSTALL_DIR/frps $BIN_DIR/frps
    
    # 创建配置文件
    if [ ! -f $CONFIG_DIR/frps.ini ]; then
        show_message info "创建默认配置文件..."
        cat > $CONFIG_DIR/frps.ini << EOF
[common]
bind_port = 7000
token = your_token_here
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin
enable_prometheus = true
EOF
        show_message warning "请编辑 $CONFIG_DIR/frps.ini 修改默认配置"
    fi
    
    # 创建systemd服务文件
    cat > $SERVICE_FILE << EOF
[Unit]
Description=Frp Server Service
After=network.target

[Service]
Type=simple
User=nobody
Restart=on-failure
RestartSec=5s
ExecStart=$BIN_DIR/frps -c $CONFIG_DIR/frps.ini
ExecReload=/bin/kill -s HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
    
    # 设置权限
    chmod 644 $CONFIG_DIR/frps.ini
    chmod 755 $BIN_DIR/frps
    chmod 644 $SERVICE_FILE
    
    # 重载systemd
    systemctl daemon-reload
    
    # 启用开机启动
    systemctl enable $SERVICE_NAME > /dev/null 2>&1
    
    # 启动服务
    systemctl start $SERVICE_NAME
    
    show_message success "Frps 安装完成!"
    
    # 清理临时文件
    rm -f /tmp/frp.tar.gz
}

# 安装管理脚本
install_manager() {
    show_message info "正在安装管理脚本..."
    
    cat > $MANAGER_FILE << 'EOF'
#!/bin/bash

SERVICE_NAME="frps"
CONFIG_DIR="/etc/frp"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示带颜色的消息
show_message() {
    case $1 in
        success) echo -e "${GREEN}$2${NC}";;
        error) echo -e "${RED}$2${NC}";;
        warning) echo -e "${YELLOW}$2${NC}";;
        info) echo -e "${BLUE}$2${NC}";;
    esac
}

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 此操作需要root权限，请使用sudo运行${NC}" >&2
        exit 1
    fi
}

# 显示服务状态
show_status() {
    echo "========================================"
    echo "          Frp Server 状态"
    echo "========================================"
    systemctl status $SERVICE_NAME -l
    echo "========================================"
    
    # 显示配置文件位置
    echo "配置文件: $CONFIG_DIR/frps.ini"
    
    # 显示监听端口
    if command -v ss &> /dev/null; then
        echo -e "\n当前监听端口:"
        ss -tlnp | grep frps || echo "未找到frps监听端口"
    fi
    
    # 显示日志
    echo -e "\n最近日志 (按q退出查看):"
    journalctl -u $SERVICE_NAME -n 20 --no-pager
}

# 重载服务配置
reload_config() {
    check_root
    show_message info "正在重载服务配置..."
    
    # 重载systemd
    systemctl daemon-reload
    systemctl restart $SERVICE_NAME
    
    show_message success "服务配置已重载"
}

# 启动服务
start_service() {
    check_root
    show_message info "正在启动Frp Server..."
    
    systemctl start $SERVICE_NAME
    sleep 2
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        show_message success "Frp Server 启动成功"
    else
        show_message error "Frp Server 启动失败"
    fi
}

# 停止服务
stop_service() {
    check_root
    show_message info "正在停止Frp Server..."
    
    systemctl stop $SERVICE_NAME
    sleep 1
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        show_message error "Frp Server 停止失败"
    else
        show_message success "Frp Server 已停止"
    fi
}

# 重启服务
restart_service() {
    check_root
    show_message info "正在重启Frp Server..."
    
    systemctl restart $SERVICE_NAME
    sleep 2
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        show_message success "Frp Server 重启成功"
    else
        show_message error "Frp Server 重启失败"
    fi
}

# 查看配置文件
view_config() {
    if [ -f "$CONFIG_DIR/frps.ini" ]; then
        echo "========================================"
        echo "          当前配置文件内容"
        echo "========================================"
        cat "$CONFIG_DIR/frps.ini"
        echo "========================================"
    else
        show_message error "配置文件不存在: $CONFIG_DIR/frps.ini"
    fi
}

# 编辑配置文件
edit_config() {
    if [ -f "$CONFIG_DIR/frps.ini" ]; then
        ${EDITOR:-vi} "$CONFIG_DIR/frps.ini"
        read -p "是否要重启服务使配置生效？(y/n): " restart_choice
        if [[ $restart_choice == "y" || $restart_choice == "Y" ]]; then
            restart_service
        fi
    else
        show_message error "配置文件不存在: $CONFIG_DIR/frps.ini"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo "========================================"
    echo "        Frp Server 管理工具"
    echo "========================================"
    echo "1. 查看服务状态"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 重载服务配置"
    echo "6. 查看配置文件"
    echo "7. 编辑配置文件"
    echo "8. 查看日志"
    echo "9. 卸载Frp Server"
    echo "0. 退出"
    echo "========================================"
}

# 主菜单
main_menu() {
    while true; do
        show_menu
        read -p "请选择操作 [0-9]: " choice
        
        case $choice in
            1) show_status;;
            2) start_service;;
            3) stop_service;;
            4) restart_service;;
            5) reload_config;;
            6) view_config;;
            7) edit_config;;
            8) 
                journalctl -u $SERVICE_NAME -f --no-pager
                ;;
            9)
                read -p "确定要卸载Frp Server吗？此操作不可逆！(y/n): " confirm
                if [[ $confirm == "y" || $confirm == "Y" ]]; then
                    uninstall_frps
                fi
                ;;
            0) echo "退出..."; exit 0;;
            *) show_message error "无效选择";;
        esac
        
        if [ $choice -ne 0 ] && [ $choice -ne 8 ]; then
            echo ""
            read -p "按回车键继续..."
        fi
    done
}

# 卸载函数
uninstall_frps() {
    check_root
    echo "========================================"
    echo "          卸载 Frp Server"
    echo "========================================"
    
    # 停止服务
    systemctl stop $SERVICE_NAME 2>/dev/null
    systemctl disable $SERVICE_NAME 2>/dev/null
    
    # 删除服务文件
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    
    # 重载systemd
    systemctl daemon-reload
    
    # 删除二进制文件
    rm -f /usr/local/bin/frps
    
    # 删除配置文件（询问）
    read -p "是否删除配置文件 /etc/frp/frps.ini？(y/n): " del_config
    if [[ $del_config == "y" || $del_config == "Y" ]]; then
        rm -f /etc/frp/frps.ini
    fi
    
    # 删除管理脚本
    rm -f /usr/local/bin/frp_manager
    
    echo "========================================"
    show_message success "Frp Server 已卸载完成"
    echo "========================================"
    exit 0
}

# 命令行参数处理
case "$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        show_status
        ;;
    reload)
        reload_config
        ;;
    config)
        view_config
        ;;
    edit)
        edit_config
        ;;
    log)
        journalctl -u $SERVICE_NAME -f --no-pager
        ;;
    uninstall)
        uninstall_frps
        ;;
    *)
        if [ -t 0 ]; then
            main_menu
        else
            echo "使用: frp_manager [command]"
            echo "可用命令:"
            echo "  start     启动服务"
            echo "  stop      停止服务"
            echo "  restart   重启服务"
            echo "  status    查看状态"
            echo "  reload    重载配置"
            echo "  config    查看配置"
            echo "  edit      编辑配置"
            echo "  log       查看日志"
            echo "  uninstall 卸载服务"
            exit 1
        fi
        ;;
esac
EOF
    
    # 设置管理脚本权限
    chmod 755 $MANAGER_FILE
    
    # 创建软链接
    ln -sf $MANAGER_FILE /usr/local/bin/frp
    
    show_message success "管理脚本安装完成"
    echo "可以通过以下方式管理Frps:"
    echo "  1. 运行 'frp' 进入交互式菜单"
    echo "  2. 运行 'frp start/stop/restart/status' 快速操作"
}

# 主安装流程
main() {
    clear
    echo "========================================"
    echo "        Frp Server 安装脚本"
    echo "========================================"
    
    # 检查是否已安装
    if [ -f "$SERVICE_FILE" ]; then
        show_message warning "Frps 已经安装"
        read -p "是否重新安装？(y/n): " reinstall
        if [[ $reinstall != "y" && $reinstall != "Y" ]]; then
            echo "退出安装"
            exit 0
        fi
    fi
    
    # 安装Frps
    install_frps
    
    # 安装管理脚本
    install_manager
    
    # 显示安装完成信息
    echo ""
    echo "========================================"
    show_message success "Frp Server 安装与管理工具已就绪"
    echo "========================================"
    echo "服务名称: $SERVICE_NAME"
    echo "配置文件: $CONFIG_DIR/frps.ini"
    echo "管理命令: frp 或 frp_manager"
    echo ""
    echo "常用命令:"
    echo "  sudo frp              # 进入管理菜单"
    echo "  sudo frp status       # 查看状态"
    echo "  sudo frp start        # 启动服务"
    echo "  sudo frp stop         # 停止服务"
    echo "  sudo frp restart      # 重启服务"
    echo "  sudo frp edit         # 编辑配置"
    echo "========================================"
    
    # 启动管理菜单
    echo ""
    read -p "是否现在进入管理菜单？(y/n): " enter_menu
    if [[ $enter_menu == "y" || $enter_menu == "Y" ]]; then
        $MANAGER_FILE
    fi
}

# 执行主函数
main