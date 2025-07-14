#!/bin/bash

# Xray 多协议一键部署脚本 - Serv00/Hostuno专用版
# 使用 Xray-core 替代 sing-box（更好的FreeBSD支持）
# Version: 3.0

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 基础变量
XRAY_VERSION="1.8.7"
HOME_DIR="$HOME"
CONFIG_PATH="$HOME_DIR/.xray"
WORK_DIR="$HOME_DIR/xray"
GITHUB_URL="https://github.com/XTLS/Xray-core/releases/download"

# 创建目录
create_dirs() {
    mkdir -p "$CONFIG_PATH"
    mkdir -p "$WORK_DIR"
}

# 下载 Xray
download_xray() {
    echo -e "${GREEN}正在下载 Xray-core...${PLAIN}"
    
    # 检测系统
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    # 架构映射
    case $ARCH in
        x86_64|amd64) ARCH="64" ;;
        i686|i386) ARCH="32" ;;
        aarch64|arm64) ARCH="arm64-v8a" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${PLAIN}" && return 1 ;;
    esac
    
    # FreeBSD 使用特殊版本
    if [[ "$OS" == "freebsd" ]]; then
        DOWNLOAD_FILE="Xray-freebsd-${ARCH}.zip"
    else
        DOWNLOAD_FILE="Xray-linux-${ARCH}.zip"
    fi
    
    DOWNLOAD_URL="${GITHUB_URL}/v${XRAY_VERSION}/${DOWNLOAD_FILE}"
    
    cd "$WORK_DIR"
    
    # 下载
    echo -e "${YELLOW}下载地址: $DOWNLOAD_URL${PLAIN}"
    curl -L -o xray.zip "$DOWNLOAD_URL"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载失败！尝试备用方案...${PLAIN}"
        # 尝试下载预编译的静态版本
        download_static_binary
        return
    fi
    
    # 解压
    unzip -o xray.zip
    chmod +x xray
    rm -f xray.zip
    
    # 测试
    if ./xray version &>/dev/null; then
        echo -e "${GREEN}Xray 安装成功！${PLAIN}"
        ./xray version
    else
        echo -e "${YELLOW}Xray 无法直接运行，尝试静态编译版...${PLAIN}"
        download_static_binary
    fi
}

# 下载静态编译版本
download_static_binary() {
    echo -e "${GREEN}正在下载静态编译版 Xray...${PLAIN}"
    
    # 使用 CGO_ENABLED=0 编译的版本
    STATIC_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip"
    
    curl -L -o xray-static.zip "$STATIC_URL"
    unzip -o xray-static.zip xray
    chmod +x xray
    rm -f xray-static.zip
    
    # 如果还是不行，使用 Go 版本
    if ! ./xray version &>/dev/null; then
        echo -e "${YELLOW}尝试使用 Go 编译版...${PLAIN}"
        use_go_binary
    fi
}

# 使用 Go 编译（最后的备选方案）
use_go_binary() {
    echo -e "${GREEN}使用预编译的通用版本...${PLAIN}"
    
    # 下载通用的 x86_64 静态链接版本
    curl -L -o xray "https://github.com/XTLS/Xray-core/releases/download/v1.8.7/xray-linux-amd64"
    chmod +x xray
    
    # 创建一个包装脚本来处理兼容性问题
    cat > "$WORK_DIR/xray-wrapper" <<'EOF'
#!/bin/sh
# Xray wrapper for FreeBSD compatibility
export LD_LIBRARY_PATH=/usr/local/lib/compat/linux:$LD_LIBRARY_PATH
exec "$(dirname "$0")/xray" "$@"
EOF
    chmod +x "$WORK_DIR/xray-wrapper"
    
    # 使用包装脚本
    if [[ -f "$WORK_DIR/xray-wrapper" ]]; then
        mv xray xray.real
        mv xray-wrapper xray
    fi
}

# 生成随机端口
generate_random_port() {
    local min_port=10000
    local max_port=65000
    while true; do
        port=$((RANDOM % ($max_port - $min_port + 1) + $min_port))
        # 使用 sockstat 检查端口（FreeBSD）
        if command -v sockstat &> /dev/null; then
            if ! sockstat -4 -l | grep -q ":$port"; then
                echo $port
                return
            fi
        else
            if ! netstat -an | grep -q ":$port "; then
                echo $port
                return
            fi
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

# 生成 VLESS + Reality 配置
generate_reality_config() {
    local port=$(generate_random_port)
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen || echo "$(openssl rand -hex 16)-$(openssl rand -hex 16)")
    local private_key=$(openssl rand -base64 32)
    local public_key=$(echo "$private_key" | openssl dgst -sha256 -binary | openssl enc -base64)
    local short_id=$(openssl rand -hex 8)
    local server_ip=$(get_public_ip)
    
    echo -e "${GREEN}生成 Reality 配置...${PLAIN}"
    echo -e "端口: ${YELLOW}$port${PLAIN}"
    
    # 创建 Xray 配置
    cat > "$CONFIG_PATH/config_reality_$port.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": [
            "www.microsoft.com"
          ],
          "privateKey": "$private_key",
          "shortIds": [
            "$short_id"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    # 生成客户端配置
    echo -e "\n${GREEN}=== Reality 配置信息 ===${PLAIN}"
    echo -e "地址: ${YELLOW}$server_ip${PLAIN}"
    echo -e "端口: ${YELLOW}$port${PLAIN}"
    echo -e "UUID: ${YELLOW}$uuid${PLAIN}"
    echo -e "流控: ${YELLOW}xtls-rprx-vision${PLAIN}"
    echo -e "加密: ${YELLOW}none${PLAIN}"
    echo -e "网络: ${YELLOW}tcp${PLAIN}"
    echo -e "TLS: ${YELLOW}reality${PLAIN}"
    echo -e "公钥: ${YELLOW}$public_key${PLAIN}"
    echo -e "短ID: ${YELLOW}$short_id${PLAIN}"
    echo -e "SNI: ${YELLOW}www.microsoft.com${PLAIN}"
    
    # 生成分享链接
    local share_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp#Reality-${port}"
    echo -e "\n${GREEN}分享链接:${PLAIN}"
    echo -e "${YELLOW}$share_link${PLAIN}"
    
    # 保存配置
    save_config_info "Reality" "$port" "$share_link" "$uuid"
    
    # 创建启动脚本
    create_start_script "reality" "$port"
}

# 生成 Shadowsocks 配置
generate_ss_config() {
    local port=$(generate_random_port)
    local password=$(openssl rand -base64 16)
    local server_ip=$(get_public_ip)
    
    echo -e "${GREEN}生成 Shadowsocks 配置...${PLAIN}"
    echo -e "端口: ${YELLOW}$port${PLAIN}"
    
    # 创建配置
    cat > "$CONFIG_PATH/config_ss_$port.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "shadowsocks",
      "settings": {
        "method": "chacha20-ietf-poly1305",
        "password": "$password"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    echo -e "\n${GREEN}=== Shadowsocks 配置信息 ===${PLAIN}"
    echo -e "地址: ${YELLOW}$server_ip${PLAIN}"
    echo -e "端口: ${YELLOW}$port${PLAIN}"
    echo -e "密码: ${YELLOW}$password${PLAIN}"
    echo -e "加密: ${YELLOW}chacha20-ietf-poly1305${PLAIN}"
    
    # 生成分享链接
    local userinfo=$(echo -n "chacha20-ietf-poly1305:${password}" | base64 -w 0)
    local share_link="ss://${userinfo}@${server_ip}:${port}#SS-${port}"
    echo -e "\n${GREEN}分享链接:${PLAIN}"
    echo -e "${YELLOW}$share_link${PLAIN}"
    
    # 保存配置
    save_config_info "Shadowsocks" "$port" "$share_link" "$password"
    
    # 创建启动脚本
    create_start_script "ss" "$port"
}

# 生成 VMess 配置
generate_vmess_config() {
    local port=$(generate_random_port)
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen || echo "$(openssl rand -hex 16)-$(openssl rand -hex 16)")
    local server_ip=$(get_public_ip)
    
    echo -e "${GREEN}生成 VMess 配置...${PLAIN}"
    echo -e "端口: ${YELLOW}$port${PLAIN}"
    
    # 创建配置
    cat > "$CONFIG_PATH/config_vmess_$port.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

    echo -e "\n${GREEN}=== VMess 配置信息 ===${PLAIN}"
    echo -e "地址: ${YELLOW}$server_ip${PLAIN}"
    echo -e "端口: ${YELLOW}$port${PLAIN}"
    echo -e "UUID: ${YELLOW}$uuid${PLAIN}"
    echo -e "加密: ${YELLOW}auto${PLAIN}"
    echo -e "网络: ${YELLOW}tcp${PLAIN}"
    
    # 生成 VMess 链接（base64格式）
    local vmess_json="{\"v\":\"2\",\"ps\":\"VMess-${port}\",\"add\":\"${server_ip}\",\"port\":${port},\"id\":\"${uuid}\",\"aid\":0,\"net\":\"tcp\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"tls\":\"\"}"
    local share_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
    
    echo -e "\n${GREEN}分享链接:${PLAIN}"
    echo -e "${YELLOW}$share_link${PLAIN}"
    
    # 保存配置
    save_config_info "VMess" "$port" "$share_link" "$uuid"
    
    # 创建启动脚本
    create_start_script "vmess" "$port"
}

# 保存配置信息
save_config_info() {
    local protocol=$1
    local port=$2
    local link=$3
    local extra=$4
    
    cat >> "$CONFIG_PATH/configs.txt" <<EOF
========================================
协议: $protocol
端口: $port
时间: $(date)
链接: $link
额外信息: $extra
========================================

EOF
}

# 创建启动脚本
create_start_script() {
    local protocol=$1
    local port=$2
    
    cat > "$WORK_DIR/start_${protocol}_${port}.sh" <<EOF
#!/bin/bash
cd $WORK_DIR
nohup ./xray run -c "$CONFIG_PATH/config_${protocol}_$port.json" > "$CONFIG_PATH/${protocol}_$port.log" 2>&1 &
echo \$! > "$CONFIG_PATH/${protocol}_$port.pid"
echo "${protocol} 服务已在端口 $port 启动"
echo "日志文件: $CONFIG_PATH/${protocol}_$port.log"
EOF
    
    chmod +x "$WORK_DIR/start_${protocol}_${port}.sh"
}

# 启动服务
start_service() {
    echo -e "${GREEN}=== 可用的启动脚本 ===${PLAIN}"
    ls -1 "$WORK_DIR"/start_*.sh 2>/dev/null
    
    echo -e "\n${YELLOW}1. 启动单个服务${PLAIN}"
    echo -e "${YELLOW}2. 启动所有服务${PLAIN}"
    read -p "请选择: " choice
    
    case $choice in
        1)
            read -p "输入脚本名称: " script
            if [[ -f "$WORK_DIR/$script" ]]; then
                bash "$WORK_DIR/$script"
            fi
            ;;
        2)
            for script in "$WORK_DIR"/start_*.sh; do
                if [[ -f "$script" ]]; then
                    bash "$script"
                    sleep 1
                fi
            done
            ;;
    esac
}

# 查看状态
check_status() {
    echo -e "${GREEN}=== 运行中的 Xray 进程 ===${PLAIN}"
    ps aux | grep "[x]ray run" || echo "没有运行中的进程"
    
    echo -e "\n${GREEN}=== 监听端口 ===${PLAIN}"
    sockstat -4 -l | grep xray || netstat -an | grep LISTEN | grep xray || echo "没有监听端口"
}

# 停止服务
stop_service() {
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
}

# 显示菜单
show_menu() {
    clear
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${GREEN}  Xray 多协议部署脚本 v3.0 (Serv00/Hostuno版) ${PLAIN}"
    echo -e "${GREEN}================================================${PLAIN}"
    echo -e "${YELLOW}1.${PLAIN} 安装 Xray"
    echo -e "${YELLOW}2.${PLAIN} 配置 VLESS + Reality (推荐)"
    echo -e "${YELLOW}3.${PLAIN} 配置 VMess"
    echo -e "${YELLOW}4.${PLAIN} 配置 Shadowsocks"
    echo -e "${YELLOW}5.${PLAIN} 查看配置信息"
    echo -e "${YELLOW}6.${PLAIN} 启动服务"
    echo -e "${YELLOW}7.${PLAIN} 停止服务"
    echo -e "${YELLOW}8.${PLAIN} 查看状态"
    echo -e "${YELLOW}9.${PLAIN} 查看日志"
    echo -e "${YELLOW}0.${PLAIN} 退出"
    echo -e "${GREEN}================================================${PLAIN}"
}

# 查看日志
view_logs() {
    echo -e "${GREEN}=== 日志文件 ===${PLAIN}"
    ls -1 "$CONFIG_PATH"/*.log 2>/dev/null
    read -p "输入日志文件名: " logfile
    if [[ -f "$CONFIG_PATH/$logfile" ]]; then
        tail -f "$CONFIG_PATH/$logfile"
    fi
}

# 查看配置
view_configs() {
    if [[ -f "$CONFIG_PATH/configs.txt" ]]; then
        cat "$CONFIG_PATH/configs.txt"
    else
        echo -e "${YELLOW}暂无配置信息${PLAIN}"
    fi
}

# 主函数
main() {
    create_dirs
    
    while true; do
        show_menu
        read -p "请选择 [0-9]: " choice
        
        case $choice in
            1) download_xray ;;
            2) generate_reality_config ;;
            3) generate_vmess_config ;;
            4) generate_ss_config ;;
            5) view_configs ;;
            6) start_service ;;
            7) stop_service ;;
            8) check_status ;;
            9) view_logs ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选项${PLAIN}" ;;
        esac
        
        read -p "按任意键继续..." -n 1
    done
}

# 运行
main
