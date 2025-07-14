#!/bin/bash

# Sing-box 多协议一键部署脚本
# 支持 Reality, Hysteria2, Trojan-Go, Shadowsocks 2022
# Author: Custom Script
# Version: 1.0

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 基础变量
SING_BOX_VERSION="1.8.0"
CONFIG_PATH="/etc/sing-box"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
GITHUB_URL="https://github.com/SagerNet/sing-box/releases/download"

# 检查系统
check_system() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
    
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}无法检测系统版本！${PLAIN}"
        exit 1
    fi
    
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
}

# 安装依赖
install_dependencies() {
    echo -e "${GREEN}正在安装依赖...${PLAIN}"
    if [[ $OS == "ubuntu" ]] || [[ $OS == "debian" ]]; then
        apt update -y
        apt install -y curl wget jq qrencode net-tools
    elif [[ $OS == "centos" ]] || [[ $OS == "fedora" ]]; then
        yum install -y epel-release
        yum install -y curl wget jq qrencode net-tools
    fi
}

# 下载 Sing-box
download_singbox() {
    echo -e "${GREEN}正在下载 Sing-box...${PLAIN}"
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${PLAIN}" && exit 1 ;;
    esac
    
    DOWNLOAD_URL="${GITHUB_URL}/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${ARCH}.tar.gz"
    
    wget -O /tmp/sing-box.tar.gz $DOWNLOAD_URL
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载失败！${PLAIN}"
        exit 1
    fi
    
    cd /tmp
    tar -xzf sing-box.tar.gz
    cp sing-box-*/sing-box /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    
    # 创建配置目录
    mkdir -p $CONFIG_PATH
}

# 生成随机端口
generate_random_port() {
    local min_port=10000
    local max_port=65000
    while true; do
        port=$((RANDOM % ($max_port - $min_port + 1) + $min_port))
        # 检查端口是否被占用
        if ! netstat -tuln | grep -q ":$port "; then
            echo $port
            return
        fi
    done
}

# 保存配置信息
save_config_info() {
    local protocol=$1
    local port=$2
    local info=$3
    
    cat >> $CONFIG_PATH/client_configs.txt <<EOF
===============================================
协议: $protocol
端口: $port
时间: $(date)
===============================================
$info

EOF
}

# 生成 Reality 配置
generate_reality_config() {
    local port=${1:-$(generate_random_port)}
    local uuid=$(sing-box generate uuid)
    local reality_private_key=$(sing-box generate reality-keypair | grep "PrivateKey" | cut -d' ' -f2)
    local reality_public_key=$(sing-box generate reality-keypair | grep "PublicKey" | cut -d' ' -f2)
    local short_id=$(openssl rand -hex 8)
    
    cat > $CONFIG_PATH/reality.json <<EOF
{
    "type": "vless",
    "tag": "vless-reality",
    "listen": "::",
    "listen_port": $port,
    "users": [
        {
            "uuid": "$uuid",
            "flow": "xtls-rprx-vision"
        }
    ],
    "tls": {
        "enabled": true,
        "server_name": "www.microsoft.com",
        "reality": {
            "enabled": true,
            "handshake": {
                "server": "www.microsoft.com",
                "server_port": 443
            },
            "private_key": "$reality_private_key",
            "short_id": ["$short_id"]
        }
    }
}
EOF
    
    local server_ip=$(curl -s4 ip.sb || curl -s4 ifconfig.me)
    
    echo -e "${GREEN}Reality 配置信息：${PLAIN}"
    echo -e "端口: $port"
    echo -e "UUID: $uuid"
    echo -e "Public Key: $reality_public_key"
    echo -e "Short ID: $short_id"
    echo -e "SNI: www.microsoft.com"
    echo -e "服务器IP: $server_ip"
    
    # 生成分享链接
    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${reality_public_key}&sid=${short_id}&type=tcp&headerType=none#Reality-${port}"
    echo -e "\n${YELLOW}分享链接：${PLAIN}"
    echo -e "$share_link"
    
    # 生成二维码
    echo -e "\n${YELLOW}二维码：${PLAIN}"
    qrencode -t ansiutf8 "$share_link"
    
    # 保存配置信息
    local config_info="端口: $port
UUID: $uuid
Public Key: $reality_public_key
Short ID: $short_id
SNI: www.microsoft.com
服务器IP: $server_ip
分享链接: $share_link"
    
    save_config_info "Reality" "$port" "$config_info"
}

# 生成 Hysteria2 配置
generate_hysteria2_config() {
    local port=${1:-$(generate_random_port)}
    local password=$(openssl rand -base64 16)
    
    # 生成自签名证书
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout $CONFIG_PATH/server.key -out $CONFIG_PATH/server.crt -subj "/CN=bing.com" -days 36500 &>/dev/null
    
    cat > $CONFIG_PATH/hysteria2.json <<EOF
{
    "type": "hysteria2",
    "tag": "hysteria2",
    "listen": "::",
    "listen_port": $port,
    "users": [
        {
            "password": "$password"
        }
    ],
    "masquerade": "https://bing.com",
    "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CONFIG_PATH/server.crt",
        "key_path": "$CONFIG_PATH/server.key"
    }
}
EOF
    
    local server_ip=$(curl -s4 ip.sb || curl -s4 ifconfig.me)
    
    echo -e "${GREEN}Hysteria2 配置信息：${PLAIN}"
    echo -e "端口: $port"
    echo -e "密码: $password"
    echo -e "伪装网址: https://bing.com"
    echo -e "服务器IP: $server_ip"
    
    # 生成分享链接
    local share_link="hysteria2://${password}@${server_ip}:${port}/?insecure=1&sni=bing.com#Hysteria2-${port}"
    echo -e "\n${YELLOW}分享链接：${PLAIN}"
    echo -e "$share_link"
    
    # 生成二维码
    echo -e "\n${YELLOW}二维码：${PLAIN}"
    qrencode -t ansiutf8 "$share_link"
    
    # 保存配置信息
    local config_info="端口: $port
密码: $password
伪装网址: https://bing.com
服务器IP: $server_ip
分享链接: $share_link"
    
    save_config_info "Hysteria2" "$port" "$config_info"
}

# 生成 Trojan 配置
generate_trojan_config() {
    local port=${1:-$(generate_random_port)}
    local password=$(openssl rand -base64 16)
    
    cat > $CONFIG_PATH/trojan.json <<EOF
{
    "type": "trojan",
    "tag": "trojan",
    "listen": "::",
    "listen_port": $port,
    "users": [
        {
            "password": "$password"
        }
    ],
    "tls": {
        "enabled": true,
        "server_name": "trojan.example.com",
        "certificate_path": "$CONFIG_PATH/server.crt",
        "key_path": "$CONFIG_PATH/server.key"
    }
}
EOF
    
    local server_ip=$(curl -s4 ip.sb || curl -s4 ifconfig.me)
    
    echo -e "${GREEN}Trojan 配置信息：${PLAIN}"
    echo -e "端口: $port"
    echo -e "密码: $password"
    echo -e "服务器IP: $server_ip"
    
    # 生成分享链接
    local share_link="trojan://${password}@${server_ip}:${port}?security=tls&sni=trojan.example.com&allowInsecure=1#Trojan-${port}"
    echo -e "\n${YELLOW}分享链接：${PLAIN}"
    echo -e "$share_link"
    
    # 生成二维码
    echo -e "\n${YELLOW}二维码：${PLAIN}"
    qrencode -t ansiutf8 "$share_link"
    
    # 保存配置信息
    local config_info="端口: $port
密码: $password
服务器IP: $server_ip
分享链接: $share_link"
    
    save_config_info "Trojan" "$port" "$config_info"
}

# 生成 Shadowsocks 2022 配置
generate_ss2022_config() {
    local port=${1:-$(generate_random_port)}
    local password=$(openssl rand -base64 32)
    
    cat > $CONFIG_PATH/shadowsocks.json <<EOF
{
    "type": "shadowsocks",
    "tag": "shadowsocks",
    "listen": "::",
    "listen_port": $port,
    "method": "2022-blake3-aes-128-gcm",
    "password": "$password"
}
EOF
    
    local server_ip=$(curl -s4 ip.sb || curl -s4 ifconfig.me)
    
    echo -e "${GREEN}Shadowsocks 2022 配置信息：${PLAIN}"
    echo -e "端口: $port"
    echo -e "加密: 2022-blake3-aes-128-gcm"
    echo -e "密码: $password"
    echo -e "服务器IP: $server_ip"
    
    # 生成分享链接 (base64编码)
    local userinfo=$(echo -n "2022-blake3-aes-128-gcm:${password}" | base64 -w 0)
    local share_link="ss://${userinfo}@${server_ip}:${port}#SS2022-${port}"
    echo -e "\n${YELLOW}分享链接：${PLAIN}"
    echo -e "$share_link"
    
    # 生成二维码
    echo -e "\n${YELLOW}二维码：${PLAIN}"
    qrencode -t ansiutf8 "$share_link"
    
    # 保存配置信息
    local config_info="端口: $port
加密: 2022-blake3-aes-128-gcm
密码: $password
服务器IP: $server_ip
分享链接: $share_link"
    
    save_config_info "Shadowsocks 2022" "$port" "$config_info"
}

# 生成主配置文件
generate_main_config() {
    cat > $CONFIG_PATH/config.json <<EOF
{
    "log": {
        "level": "info",
        "timestamp": true
    },
    "inbounds": [],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        }
    ]
}
EOF
}

# 创建 systemd 服务
create_service() {
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_PATH/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
}

# 显示菜单
show_menu() {
    clear
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${GREEN}       Sing-box 多协议一键部署脚本 v1.0        ${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${YELLOW}1.${PLAIN} 安装 Sing-box"
    echo -e "${YELLOW}2.${PLAIN} 配置 Reality"
    echo -e "${YELLOW}3.${PLAIN} 配置 Hysteria2"
    echo -e "${YELLOW}4.${PLAIN} 配置 Trojan"
    echo -e "${YELLOW}5.${PLAIN} 配置 Shadowsocks 2022"
    echo -e "${YELLOW}6.${PLAIN} 查看配置信息"
    echo -e "${YELLOW}7.${PLAIN} 启动/停止/重启服务"
    echo -e "${YELLOW}8.${PLAIN} 查看日志"
    echo -e "${YELLOW}9.${PLAIN} 卸载 Sing-box"
    echo -e "${YELLOW}0.${PLAIN} 退出脚本"
    echo -e "${GREEN}================================================${PLAIN}"
}

# 主函数
main() {
    check_system
    
    while true; do
        show_menu
        read -p "请输入选项 [0-9]: " choice
        
        case $choice in
            1)
                install_dependencies
                download_singbox
                generate_main_config
                create_service
                echo -e "${GREEN}安装完成！${PLAIN}"
                ;;
            2)
                echo -e "${YELLOW}1. 使用随机端口（推荐）${PLAIN}"
                echo -e "${YELLOW}2. 自定义端口${PLAIN}"
                read -p "请选择: " port_choice
                
                if [[ $port_choice == "2" ]]; then
                    read -p "请输入 Reality 端口: " port
                    # 检查端口是否被占用
                    if netstat -tuln | grep -q ":$port "; then
                        echo -e "${RED}端口 $port 已被占用！${PLAIN}"
                        continue
                    fi
                else
                    port=$(generate_random_port)
                    echo -e "${GREEN}已生成随机端口: $port${PLAIN}"
                fi
                
                generate_reality_config $port
                # 保存配置信息到文件
                echo "Reality Port: $port" >> $CONFIG_PATH/ports.txt
                ;;
            3)
                echo -e "${YELLOW}1. 使用随机端口（推荐）${PLAIN}"
                echo -e "${YELLOW}2. 自定义端口${PLAIN}"
                read -p "请选择: " port_choice
                
                if [[ $port_choice == "2" ]]; then
                    read -p "请输入 Hysteria2 端口: " port
                    if netstat -tuln | grep -q ":$port "; then
                        echo -e "${RED}端口 $port 已被占用！${PLAIN}"
                        continue
                    fi
                else
                    port=$(generate_random_port)
                    echo -e "${GREEN}已生成随机端口: $port${PLAIN}"
                fi
                
                generate_hysteria2_config $port
                echo "Hysteria2 Port: $port" >> $CONFIG_PATH/ports.txt
                ;;
            4)
                echo -e "${YELLOW}1. 使用随机端口（推荐）${PLAIN}"
                echo -e "${YELLOW}2. 自定义端口${PLAIN}"
                read -p "请选择: " port_choice
                
                if [[ $port_choice == "2" ]]; then
                    read -p "请输入 Trojan 端口: " port
                    if netstat -tuln | grep -q ":$port "; then
                        echo -e "${RED}端口 $port 已被占用！${PLAIN}"
                        continue
                    fi
                else
                    port=$(generate_random_port)
                    echo -e "${GREEN}已生成随机端口: $port${PLAIN}"
                fi
                
                generate_trojan_config $port
                echo "Trojan Port: $port" >> $CONFIG_PATH/ports.txt
                ;;
            5)
                echo -e "${YELLOW}1. 使用随机端口（推荐）${PLAIN}"
                echo -e "${YELLOW}2. 自定义端口${PLAIN}"
                read -p "请选择: " port_choice
                
                if [[ $port_choice == "2" ]]; then
                    read -p "请输入 Shadowsocks 端口: " port
                    if netstat -tuln | grep -q ":$port "; then
                        echo -e "${RED}端口 $port 已被占用！${PLAIN}"
                        continue
                    fi
                else
                    port=$(generate_random_port)
                    echo -e "${GREEN}已生成随机端口: $port${PLAIN}"
                fi
                
                generate_ss2022_config $port
                echo "Shadowsocks Port: $port" >> $CONFIG_PATH/ports.txt
                ;;
            6)
                echo -e "${GREEN}=== 配置文件位置 ===${PLAIN}"
                ls -la $CONFIG_PATH/
                echo ""
                
                if [[ -f $CONFIG_PATH/client_configs.txt ]]; then
                    echo -e "${GREEN}=== 客户端配置信息 ===${PLAIN}"
                    cat $CONFIG_PATH/client_configs.txt
                else
                    echo -e "${YELLOW}暂无配置信息${PLAIN}"
                fi
                
                if [[ -f $CONFIG_PATH/ports.txt ]]; then
                    echo -e "\n${GREEN}=== 端口使用情况 ===${PLAIN}"
                    cat $CONFIG_PATH/ports.txt
                fi
                ;;
            7)
                echo -e "${YELLOW}1. 启动服务${PLAIN}"
                echo -e "${YELLOW}2. 停止服务${PLAIN}"
                echo -e "${YELLOW}3. 重启服务${PLAIN}"
                read -p "请选择操作: " op
                case $op in
                    1) systemctl start sing-box && echo -e "${GREEN}启动成功${PLAIN}" ;;
                    2) systemctl stop sing-box && echo -e "${GREEN}停止成功${PLAIN}" ;;
                    3) systemctl restart sing-box && echo -e "${GREEN}重启成功${PLAIN}" ;;
                esac
                ;;
            8)
                journalctl -u sing-box -f
                ;;
            9)
                systemctl stop sing-box
                systemctl disable sing-box
                rm -rf $CONFIG_PATH
                rm -f $SERVICE_FILE
                rm -f /usr/local/bin/sing-box
                echo -e "${GREEN}卸载完成！${PLAIN}"
                ;;
            0)
                echo -e "${GREEN}感谢使用！${PLAIN}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项！${PLAIN}"
                ;;
        esac
        
        read -p "按任意键继续..." -n 1
    done
}

# 运行主函数
main
