# Sing-box 多协议一键部署教程

## 简介

本脚本支持以下协议的一键部署：
- **Reality** - 最新的抗检测协议，伪装能力强
- **Hysteria2** - 基于 QUIC 的高速协议，配合伪装使用
- **Trojan-Go** - 经典稳定的 TLS 伪装协议
- **Shadowsocks 2022** - 新一代加密协议

## 系统要求

- 支持系统：Ubuntu 18.04+, Debian 9+, CentOS 7+
- 需要 root 权限
- 建议内存：512MB 以上
- 架构支持：x86_64, arm64, armv7

## 安装方法

### 方法一：直接运行（推荐）

```bash
bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USERNAME/sing-box-script/main/install.sh)
```

### 方法二：下载后运行

```bash
# 下载脚本
wget -O singbox.sh https://raw.githubusercontent.com/YOUR_USERNAME/sing-box-script/main/install.sh

# 添加执行权限
chmod +x singbox.sh

# 运行脚本
./singbox.sh
```

## 使用步骤

### 1. 初次安装

运行脚本后，首先选择选项 `1` 安装 Sing-box：

```bash
请输入选项 [0-9]: 1
```

这将自动：
- 检测系统环境
- 安装必要依赖
- 下载最新版 Sing-box
- 创建系统服务

### 2. 配置协议

根据需要选择要配置的协议，脚本会提供两种端口选择方式：

1. **随机端口（推荐）** - 自动生成 10000-65000 之间的未占用端口
2. **自定义端口** - 手动指定端口号

#### Reality 配置（推荐）
```bash
请输入选项 [0-9]: 2
1. 使用随机端口（推荐）
2. 自定义端口
请选择: 1
已生成随机端口: 34567
```

脚本会自动：
- 生成随机未占用端口
- 生成 UUID 和密钥
- 显示分享链接
- 生成二维码
- 保存配置信息到 `/etc/sing-box/client_configs.txt`

**Reality 优势**：
- 最难被检测和识别
- 伪装成标准 TLS 1.3 流量
- 支持 XTLS Vision 流控

#### Hysteria2 配置
```bash
请输入选项 [0-9]: 3
请输入 Hysteria2 端口 (默认 8443): 8443
```

**配置建议**：
- 使用非标准端口（如 8443, 10443）
- 配合伪装域名使用（默认 bing.com）

#### Trojan 配置
```bash
请输入选项 [0-9]: 4
请输入 Trojan 端口 (默认 8444): 8444
```

#### Shadowsocks 2022 配置
```bash
请输入选项 [0-9]: 5
请输入 Shadowsocks 端口 (默认 8388): 8388
```

### 3. 客户端配置

配置完成后，脚本会显示相应的连接信息。

#### Reality 客户端配置示例
```json
{
  "type": "vless",
  "server": "你的服务器IP",
  "server_port": 443,
  "uuid": "生成的UUID",
  "flow": "xtls-rprx-vision",
  "tls": {
    "enabled": true,
    "server_name": "www.microsoft.com",
    "reality": {
      "enabled": true,
      "public_key": "生成的公钥",
      "short_id": "生成的短ID"
    }
  }
}
```

#### Hysteria2 客户端链接
```
hysteria2://密码@服务器IP:端口/?insecure=1&sni=bing.com
```

### 4. 服务管理

```bash
# 查看服务状态
systemctl status sing-box

# 启动服务
systemctl start sing-box

# 停止服务
systemctl stop sing-box

# 重启服务
systemctl restart sing-box

# 查看日志
journalctl -u sing-box -f
```

## 防火墙配置

确保开放相应端口：

```bash
# Ubuntu/Debian
ufw allow 443/tcp
ufw allow 8443/udp
ufw allow 8444/tcp
ufw allow 8388/tcp

# CentOS/RHEL
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=8443/udp
firewall-cmd --permanent --add-port=8444/tcp
firewall-cmd --permanent --add-port=8388/tcp
firewall-cmd --reload
```

## 优化建议

### 1. BBR 加速

```bash
# 开启 BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
```

### 2. 系统优化

```bash
# 优化文件描述符
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf
```

### 3. 协议选择建议

- **日常使用**：Reality + Shadowsocks 2022 组合
- **高速需求**：Hysteria2（注意伪装）
- **稳定优先**：Trojan-Go
- **移动网络**：Reality（抗干扰能力强）

## 故障排查

### 服务无法启动
```bash
# 检查配置文件
sing-box check -c /etc/sing-box/config.json

# 查看详细日志
journalctl -u sing-box -n 50
```

### 连接失败
1. 检查防火墙规则
2. 确认服务器 IP 是否正确
3. 验证端口是否被占用：`netstat -tlnp | grep 端口号`

### 速度慢
1. 尝试更换协议
2. 调整服务器位置
3. 使用 BBR 加速

## 更新维护

```bash
# 更新 Sing-box
./singbox.sh
选择选项 1 重新安装即可

# 备份配置
cp -r /etc/sing-box /etc/sing-box.bak
```

## 安全建议

1. **定期更换密码/UUID**
2. **使用非标准端口**
3. **启用防火墙**
4. **定期更新系统和 Sing-box**
5. **监控服务器流量**

## 常见问题

**Q: Reality 和 VLESS 有什么区别？**
A: Reality 是 VLESS 的升级版，具有更强的伪装能力。

**Q: 哪个协议最不容易被限速？**
A: Reality 和正确配置的 Trojan 最不容易被识别和限速。

**Q: 可以同时运行多个协议吗？**
A: 可以，只要端口不冲突即可。

**Q: 如何选择合适的端口？**
A: 建议使用常见的 HTTPS 端口如 443, 8443，或者企业常用端口如 8080, 10443。

## 特别说明 - 共享VPS使用

对于共享型VPS（如Serv00、Hostuno等），本脚本特别优化了以下功能：

### 自动随机端口
- 默认生成 10000-65000 范围内的随机端口
- 自动检测端口占用情况
- 避免与其他用户冲突

### 端口管理
所有生成的端口信息会保存在：
- `/etc/sing-box/ports.txt` - 端口列表
- `/etc/sing-box/client_configs.txt` - 完整配置信息

### 查看配置
```bash
# 查看所有配置信息
cat /etc/sing-box/client_configs.txt

# 只查看端口信息
cat /etc/sing-box/ports.txt
```

## 免责声明

本脚本仅供学习和研究使用，请遵守当地法律法规。作者不对使用本脚本产生的任何后果负责。
