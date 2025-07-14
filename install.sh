#!/bin/bash

# Sing-box 多协议一键部署脚本 - 共享VPS版本
# 支持 Reality, Hysteria2, Trojan-Go, Shadowsocks 2022
# 适用于无root权限的共享VPS环境
# Version: 2.0

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 基础变量
SING_BOX_VERSION="1.8.0"
HOME_DIR="$HOME"
CONFIG_PATH="$HOME_DIR/.sing-box"
WORK_DIR="$HOME_DIR/sing-box"
SERVICE_FILE="$HOME_DIR/sing-box.service"
GITHUB_URL="https://github.com/SagerNet/sing-box/releases/download"

# 检查系统
check_system() {
    echo -e "${GREEN}检测到共享VPS环境，使用用户权限安装${PLAIN}"
    
    # 创建必要目录
    mkdir -p "$CONFIG_PATH"
    mkdir -p "$WORK_DIR"
    
    # 检查系统架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${PLAIN}" && exit 1 ;;
    esac
}

# 下载 Sing-box
download_singbox() {
    echo -e "${GREEN}正在下载 Sing-box...${PLAIN}"
    
    DOWNLOAD_URL="${GITHUB_URL}/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${ARCH}.tar.gz"
    
    cd "$WORK_DIR"
    wget -O sing-box.tar.gz $DOWNLOAD_URL
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载失败！${PLAIN}"
        exit 1
    fi
    
    tar -xzf sing-box.tar.gz
    cp sing-box-*/sing-box ./
    chmod +x sing-box
    rm -rf sing-box-* sing-box.tar.gz
    
    echo -e "${GREEN}Sing-box 下载完成！${PLAIN}"
}

# 生成随机端口
generate_random_port() {
    local min_port=10000
    local max_port=65000
    while true; do
        port=$((RANDOM % ($max_port - $min_port + 1) + $min_port))
        # 检查端口是否被占用
        if ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo $port
            return
        fi
    done
}

# 获取公网IP
get_public_ip() {
    local ip=$(curl -s4 ip.sb || curl -s4 ifconfig.me || curl -s4 ipinfo.io/ip)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s6 ip.sb || curl -s6 ifconfig.me || curl -s6 ipinfo.io/ip)
    fi
    echo "$ip"
}

# 保存配置信息
save_config_info() {
    local protocol=$1
    local port=$2
    local info=$3
    
    cat >> "$CONFIG_PATH/client_configs.txt" <<EOF
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
    echo -e "${YELLOW}1. 使用随机端口（推荐）${PLAIN}"
    echo -e "${YELLOW}2. 自定义端口${PLAIN}"
    read -p "请选择: " port_choice
    
    if [[ $port_choice == "2" ]]; then
        read -p "请输入 Reality 端口: " port
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "${RED}端口 $port 已被占用！${PLAIN}"
            return
        fi
    else
        port=$(generate_random_port)
        echo -e "${GREEN}已生成随机端口: $port${PLAIN}"
    fi
    
    # 生成密钥对
    local keypair=$("$WORK_DIR/sing-box" generate reality-keypair)
    local private_key=$(echo "$keypair" | grep "PrivateKey" | awk '{print $2}')
    local public_key=$(echo "$keypair" | grep "PublicKey" | awk '{print $2}')
    local uuid=$("$WORK_DIR/sing-box" generate uuid)
    local short_id=$(openssl rand -hex 8)
    
    # 创建配置
    cat > "$CONFIG_PATH/config_reality_$port.json" <<EOF
{
    "log": {
        "level": "info"
    },
    "inbounds": [
        {
            "type": "vless",
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
                    "private_key": "$private_key",
                    "short_id": ["$short_id"]
                }
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF
    
    local server_ip=$(get_public_ip)
    
    echo -e "${GREEN}Reality 配置信息：${PLAIN}"
    echo -e "端口: $port"
    echo -e "UUID: $uuid"
    echo -e "Public Key: $public_key"
    echo -e "Short ID: $short_id"
    echo -e "SNI: www.microsoft.com"
    echo -e "服务器IP: $server_ip"
    
    # 生成分享链接
    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#Reality-${port}"
    echo -e "\n${YELLOW}分享链接：${PLAIN}"
    echo -e "$share_link"
    
    # 生成二维码（如果有qrencode）
    if command -v qrencode &> /dev/null; then
        echo -e "\n${YELLOW}二维码：${PLAIN}"
        qrencode -t ansiutf8 "$share_link"
    fi
    
    # 保存配置信息
    local config_info="端口: $port
UUID: $uuid
Public Key: $public_key
Short ID: $short_id
SNI: www.microsoft.com
服务器IP: $server_ip
分享链接: $share_link"
    
    save_config_info "Reality" "$port" "$config_info"
    
    # 创建启动脚本
    create_start_script "reality" "$port"
}

# 生成 Hysteria2 配置
generate_hysteria2_config() {
    echo -e "${YELLOW}1. 使用随机端口（推荐）${PLAIN}"
    echo -e "${YELLOW}2. 自定义端口${PLAIN}"
    read -p "请选择: " port_choice
    
    if [[ $port_choice == "2" ]]; then
        read -p "请输入 Hysteria2 端口: " port
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "${RED}端口 $port 已被占用！${PLAIN}"
            return
        fi
    else
        port=$(generate_random_port)
        echo -e "${GREEN}已生成随机端口: $port${PLAIN}"
    fi
    
    local password=$(openssl rand -base64 16)
    
    # 生成自签名证书
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "$CONFIG_PATH/server_hy2_$port.key" \
        -out "$CONFIG_PATH/server_hy2_$port.crt" \
        -subj "/CN=bing.com" -days 36500 &>/dev/null
    
    cat > "$CONFIG_PATH/config_hysteria2_$port.json" <<EOF
{
    "log": {
        "level": "info"
    },
    "inbounds": [
        {
            "type": "hysteria2",
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
                "certificate_path": "$CONFIG_PATH/server_hy2_$port.crt",
                "key_path": "$CONFIG_PATH/server_hy2_$port.key"
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF
    
    local server_ip=$(get_public_ip)
    
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
    if command -v qrencode &> /dev/null; then
        echo -e "\n${YELLOW}二维码：${PLAIN}"
        qrencode -t ansiutf8 "$share_link"
    fi
    
    # 保存配置信息
    local config_info="端口: $port
密码: $password
伪装网址: https://bing.com
服务器IP: $server_ip
分享链接: $share_link"
    
    save_config_info "Hysteria2" "$port" "$config_info"
    
    # 创建启动脚本
    create_start_script "hysteria2" "$port"
}

# 生成 Shadowsocks 2022 配置
generate_ss2022_config() {
    echo -e "${YELLOW}1. 使用随机端口（推荐）${PLAIN}"
    echo -e "${YELLOW}2. 自定义端口${PLAIN}"
    read -p "请选择: " port_choice
    
    if [[ $port_choice == "2" ]]; then
        read -p "请输入 Shadowsocks 端口: " port
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "${RED}端口 $port 已被占用！${PLAIN}"
            return
        fi
    else
        port=$(generate_random_port)
        echo -e "${GREEN}已生成随机端口: $port${PLAIN}"
    fi
    
    # 使用16字节密钥以兼容 2022-blake3-aes-128-gcm
    local password=$(openssl rand -base64 16)
    
    cat > "$CONFIG_PATH/config_ss_$port.json" <<EOF
{
    "log": {
        "level": "info"
    },
    "inbounds": [
        {
            "type": "shadowsocks",
            "listen": "::",
            "listen_port": $port,
            "method": "2022-blake3-aes-128-gcm",
            "password": "$password"
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF
    
    local server_ip=$(get_public_ip)
    
    echo -e "${GREEN}Shadowsocks 2022 配置信息：${PLAIN}"
    echo -e "端口: $port"
    echo -e "加密: 2022-blake3-aes-128-gcm"
    echo -e "密码: $password"
    echo -e "服务器IP: $server_ip"
    
    # 生成分享链接
    local userinfo=$(echo -n "2022-blake3-aes-128-gcm:${password}" | base64 -w 0)
    local share_link="ss://${userinfo}@${server_ip}:${port}#SS2022-${port}"
    echo -e "\n${YELLOW}分享链接：${PLAIN}"
    echo -e "$share_link"
    
    # 生成二维码
    if command -v qrencode &> /dev/null; then
        echo -e "\n${YELLOW}二维码：${PLAIN}"
        qrencode -t ansiutf8 "$share_link"
    fi
    
    # 保存配置信息
    local config_info="端口: $port
加密: 2022-blake3-aes-128-gcm
密码: $password
服务器IP: $server_ip
分享链接: $share_link"
    
    save_config_info "Shadowsocks 2022" "$port" "$config_info"
    
    # 创建启动脚本
    create_start_script "shadowsocks" "$port"
}

# 创建启动脚本
create_start_script() {
    local protocol=$1
    local port=$2
    local script_name="start_${protocol}_${port}.sh"
    
    cat > "$WORK_DIR/$script_name" <<EOF
#!/bin/bash
cd $WORK_DIR
nohup ./sing-box run -c "$CONFIG_PATH/config_${protocol}_$port.json" > "$CONFIG_PATH/${protocol}_$port.log" 2>&1 &
echo \$! > "$CONFIG_PATH/${protocol}_$port.pid"
echo "${protocol} 已在端口 $port 启动"
EOF
    
    chmod +x "$WORK_DIR/$script_name"
    echo -e "${GREEN}启动脚本已创建: $script_name${PLAIN}"
}

# 查看运行状态
check_status() {
    echo -e "${GREEN}=== 运行中的 Sing-box 进程 ===${PLAIN}"
    ps aux | grep sing-box | grep -v grep
    
    echo -e "\n${GREEN}=== 端口监听状态 ===${PLAIN}"
    netstat -tuln 2>/dev/null | grep sing-box || echo "未找到 sing-box 监听端口"
    
    echo -e "\n${GREEN}=== PID 文件 ===${PLAIN}"
    ls -la "$CONFIG_PATH"/*.pid 2>/dev/null || echo "未找到 PID 文件"
}

# 停止服务
stop_service() {
    echo -e "${YELLOW}1. 停止所有服务${PLAIN}"
    echo -e "${YELLOW}2. 停止指定端口服务${PLAIN}"
    read -p "请选择: " choice
    
    if [[ $choice == "1" ]]; then
        # 停止所有服务
        for pidfile in "$CONFIG_PATH"/*.pid; do
            if [[ -f "$pidfile" ]]; then
                pid=$(cat "$pidfile")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    echo -e "${GREEN}已停止进程 $pid${PLAIN}"
                fi
                rm -f "$pidfile"
            fi
        done
    else
        read -p "请输入要停止的端口: " port
        for pidfile in "$CONFIG_PATH"/*_${port}.pid; do
            if [[ -f "$pidfile" ]]; then
                pid=$(cat "$pidfile")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    echo -e "${GREEN}已停止端口 $port 的服务${PLAIN}"
                fi
                rm -f "$pidfile"
            fi
        done
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${GREEN}   Sing-box 多协议部署脚本 v2.0 (共享VPS版)   ${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${YELLOW}1.${PLAIN} 安装/更新 Sing-box"
    echo -e "${YELLOW}2.${PLAIN} 配置 Reality (推荐)"
    echo -e "${YELLOW}3.${PLAIN} 配置 Hysteria2"
    echo -e "${YELLOW}4.${PLAIN} 配置 Shadowsocks 2022"
    echo -e "${YELLOW}5.${PLAIN} 查看配置信息"
    echo -e "${YELLOW}6.${PLAIN} 启动服务"
    echo -e "${YELLOW}7.${PLAIN} 停止服务"
    echo -e "${YELLOW}8.${PLAIN} 查看运行状态"
    echo -e "${YELLOW}9.${PLAIN} 查看日志"
    echo -e "${YELLOW}0.${PLAIN} 退出脚本"
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${BLUE}工作目录: $WORK_DIR${PLAIN}"
    echo -e "${BLUE}配置目录: $CONFIG_PATH${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
}

# 启动服务
start_service() {
    echo -e "${GREEN}=== 可用的启动脚本 ===${PLAIN}"
    ls -1 "$WORK_DIR"/start_*.sh 2>/dev/null || echo "未找到启动脚本"
    
    echo -e "\n${YELLOW}1. 启动指定脚本${PLAIN}"
    echo -e "${YELLOW}2. 启动所有服务${PLAIN}"
    read -p "请选择: " choice
    
    if [[ $choice == "1" ]]; then
        read -p "请输入脚本名称（如 start_reality_12345.sh）: " script_name
        if [[ -f "$WORK_DIR/$script_name" ]]; then
            bash "$WORK_DIR/$script_name"
        else
            echo -e "${RED}脚本不存在！${PLAIN}"
        fi
    else
        for script in "$WORK_DIR"/start_*.sh; do
            if [[ -f "$script" ]]; then
                echo -e "${GREEN}启动 $(basename $script)${PLAIN}"
                bash "$script"
            fi
        done
    fi
}

# 查看日志
view_logs() {
    echo -e "${GREEN}=== 可用的日志文件 ===${PLAIN}"
    ls -1 "$CONFIG_PATH"/*.log 2>/dev/null || echo "未找到日志文件"
    
    read -p "请输入要查看的日志文件名（如 reality_12345.log）: " log_name
    if [[ -f "$CONFIG_PATH/$log_name" ]]; then
        tail -f "$CONFIG_PATH/$log_name"
    else
        echo -e "${RED}日志文件不存在！${PLAIN}"
    fi
}

# 主函数
main() {
    check_system
    
    while true; do
        show_menu
        read -p "请输入选项 [0-9]: " choice
        
        case $choice in
            1)
                download_singbox
                echo -e "${GREEN}安装完成！${PLAIN}"
                ;;
            2)
                generate_reality_config
                ;;
            3)
                generate_hysteria2_config
                ;;
            4)
                generate_ss2022_config
                ;;
            5)
                if [[ -f "$CONFIG_PATH/client_configs.txt" ]]; then
                    echo -e "${GREEN}=== 客户端配置信息 ===${PLAIN}"
                    cat "$CONFIG_PATH/client_configs.txt"
                else
                    echo -e "${YELLOW}暂无配置信息${PLAIN}"
                fi
                ;;
            6)
                start_service
                ;;
            7)
                stop_service
                ;;
            8)
                check_status
                ;;
            9)
                view_logs
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
