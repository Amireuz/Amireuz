#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以 root 权限运行。请使用 sudo 命令。"
    exit 1
fi

# 设置工作目录
WORK_DIR="/root/compose"
mkdir -p $WORK_DIR
cd $WORK_DIR

# 检查系统和必要工具
check_system() {
    if ! grep -Ei 'debian|ubuntu' /etc/os-release > /dev/null; then
        echo "此脚本只支持 Debian 或 Ubuntu 系统。"
        exit 1
    fi

    for tool in openssl shuf curl docker jq; do
        if ! command -v $tool &> /dev/null; then
            echo "正在安装 $tool..."
            apt-get update
            apt-get install -y $tool
        fi
    done
}

# 安装 Docker 和 Docker Compose
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "正在安装 Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
    fi

    if ! command -v docker compose &> /dev/null; then
        echo "正在安装 Docker Compose..."
        apt-get update
        apt-get install -y docker-compose-plugin
    fi
}

# 生成随机端口和密码
generate_credentials() {
    SNELL_PORT=$(shuf -i 15000-50000 -n 1)
    SNELL_PSK=$(openssl rand -base64 32)
}

# 创建 Snell 配置文件和 Dockerfile
create_configs() {
    # 创建 Snell 配置文件
    mkdir -p $WORK_DIR/snell
    cat > $WORK_DIR/snell/snell-server.conf <<EOF
[snell-server]
listen = ::0:$SNELL_PORT
psk = $SNELL_PSK
ipv6 = true
EOF

    # 创建 Snell Dockerfile
    cat > $WORK_DIR/snell/Dockerfile <<EOF
FROM debian:latest
WORKDIR /root/compose/snell
COPY snell-server /root/compose/snell/snell-server
COPY snell-server.conf /root/compose/snell/snell-server.conf
RUN chmod +x /root/compose/snell/snell-server
CMD ["./snell-server", "-c", "snell-server.conf"]
EOF

    # 创建 Docker Compose 文件
    cat > $WORK_DIR/docker-compose.yml <<EOF
services:
  snell-server:
    build: ./snell
    container_name: snell
    restart: always
    volumes:
      - ./snell/snell-server.conf:/root/compose/snell/snell-server.conf
    network_mode: "host"
    command: ["./snell-server", "-c", "/root/compose/snell/snell-server.conf"]
EOF
}

# 初始安装函数
initial_install() {
    check_system
    install_docker
    generate_credentials
    create_configs

    # 下载 Snell
    wget https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip
    unzip snell-server-v4.0.1-linux-amd64.zip -d $WORK_DIR/snell/
    rm snell-server-v4.0.1-linux-amd64.zip

    # 启动服务
    docker compose up -d
    if [ $? -ne 0 ]; then
        echo "错误：无法启动 Docker 服务。请检查 Docker Compose 文件和日志。"
        exit 1
    fi

    echo "初始安装完成。"
    display_info
}

# 更新 Snell 函数
update_snell() {
    echo "正在更新 Snell..."
    if [ ! -f "$WORK_DIR/docker-compose.yml" ]; then
        echo "错误：docker-compose.yml 文件不存在。"
        echo "您可能需要运行初始安装来生成配置文件。"
        return
    fi

    docker compose down snell-server
    docker compose pull snell-server
    docker compose up -d snell-server
    if [ $? -ne 0 ]; then
        echo "启动 Snell 服务失败。请检查配置文件和日志。"
        return
    fi

    echo "Snell 已更新并重启。"
}

# 重启 Snell 函数
restart_snell() {
    echo "正在重启 Snell..."
    if [ ! -f "$WORK_DIR/docker-compose.yml" ]; then
        echo "错误：docker-compose.yml 文件不存在。"
        return
    fi

    # 停止并重启 Snell 容器
    docker compose down snell-server
    docker compose up -d snell-server

    if [ $? -ne 0 ]; then
        echo "Snell 重启失败，请检查配置文件和日志。"
        return
    fi

    echo "Snell 已成功重启。"
}

# 删除 Snell 函数
delete_snell() {
    echo "正在删除 Snell..."
    if [ ! -f "$WORK_DIR/docker-compose.yml" ]; then
        echo "错误：docker-compose.yml 文件不存在。"
        return
    fi

    # 停止并删除 Snell 容器
    docker compose down

    # 删除 Snell 镜像
    docker rmi snell-server

    # 删除配置文件和工作目录
    rm -rf $WORK_DIR/snell
    rm -rf $WORK_DIR/docker-compose.yml

    echo "Snell 已成功删除。"
}

# 显示连接信息函数
display_info() {
    IP=$(curl -4s ifconfig.me)
    SNELL_CONFIG="$WORK_DIR/snell/snell-server.conf"

    if [ -f "$SNELL_CONFIG" ];then
        SNELL_PORT=$(grep "listen" $SNELL_CONFIG | awk -F':' '{print $NF}')
        SNELL_PSK=$(grep "psk" $SNELL_CONFIG | awk '{print $3}')
    else
        echo "Snell配置文件不存在。"
        return
    fi

    echo "(***)ₛ = snell, $IP, $SNELL_PORT, psk=$SNELL_PSK, version=4, reuse=true, tfo=true"
}

# 主菜单
main_menu() {
    while true; do
        echo ""
        echo "请选择操作："
        echo "1) 初始安装"
        echo "2) 更新 Snell"
        echo "3) 重启 Snell"
        echo "4) 显示连接信息"
        echo "5) 删除 Snell"
        echo "0) 退出脚本"
        read -p "请输入选项: " choice

        case $choice in
            1) initial_install ;;
            2) update_snell ;;
            3) restart_snell ;;
            4) display_info ;;
            5) delete_snell ;;
            0) echo "退出脚本"; exit 0 ;;
            *) echo "无效选项，请重新选择" ;;
        esac

        echo "按回车键继续..."
        read
    done
}

# 运行主菜单
main_menu
