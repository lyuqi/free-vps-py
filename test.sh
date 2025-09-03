#!/bin/bash
# =========================================
# 自控版一键部署脚本
# Author: gmddd002
# 仓库: https://github.com/gmddd002/free-vps-py
# 项目: https://github.com/gmddd002/python-xray-argo
# =========================================
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'  # 无颜色

LOGFILE="app.log"

echo -e "${GREEN}>>> 安装必要依赖...${NC}" | tee -a "$LOGFILE"
# 更新软件源并安装 Python3、pip、screen、jq 等
apt-get update
apt-get install -y python3 python3-pip screen jq curl git

echo -e "${GREEN}>>> 安装 cloudflared（Argo 隧道客户端）...${NC}" | tee -a "$LOGFILE"
# 安装 cloudflared：可通过 apt 或下载官方包
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb 2>/dev/null || apt-get install -f -y
rm -f cloudflared.deb

echo -e "${GREEN}>>> 克隆用户仓库并安装依赖...${NC}" | tee -a "$LOGFILE"
# 从用户 GitHub 仓库拉取脚本
cd /root
rm -rf python-xray-argo
git clone https://github.com/gmddd002/python-xray-argo.git
cd python-xray-argo
# 安装 Python 依赖
pip3 install -r requirements.txt

# 自动分配未占用端口（优选 20000–29999 范围）
echo -e "${GREEN}>>> 分配未占用的服务端口...${NC}" | tee -a "$LOGFILE"
while true; do
  PORT=$(python3 - <<'PYCODE'
import socket, random
while True:
    port = random.randint(20000, 29999)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        if s.connect_ex(('localhost', port)) != 0:
            print(port)
            break
PYCODE
)
  # 验证端口号是否获取成功
  if [[ -n "$PORT" ]]; then
    break
  fi
done
export PORT
echo -e "${BLUE}Allocated PORT:$NC $PORT" | tee -a "$LOGFILE"

# 启动 Xray-Argo 服务并记录日志
echo -e "${GREEN}>>> 启动 Xray-Argo 应用 (app.py)...${NC}" | tee -a "$LOGFILE"
# 使用 nohup 后台运行 app.py，并将输出同时记录到控制台和日志
nohup python3 app.py 2>&1 | tee -a "$LOGFILE" &

# 等待服务启动完成并生成所需文件
sleep 15

# 从 boot.log 中提取 trycloudflare 域名（Argo Tunnel 分配的临时地址）
ARGO_ADDR=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' boot.log | head -n1)
ARGO_ADDR=${ARGO_ADDR#https://}
echo -e "${GREEN}临时隧道地址:${NC} $ARGO_ADDR" | tee -a "$LOGFILE"

# 读取并解码订阅（Base64 内容），获得各协议链接
SUB_B64=$(cat sub.txt)
echo -e "${GREEN}Base64 订阅链接:${NC} $SUB_B64" | tee -a "$LOGFILE"
DECODED_LINKS=$(echo "$SUB_B64" | base64 -d)
echo -e "${GREEN}节点连接信息 (VLESS/VMESS/Trojan):${NC}" | tee -a "$LOGFILE"
# 分别提取三种协议的完整 URI
VLESS_URI=$(echo "$DECODED_LINKS" | grep -oE 'vless://[^ ]+')
VMESS_URI=$(echo "$DECODED_LINKS" | grep -oE 'vmess://[^ ]+')
TROJAN_URI=$(echo "$DECODED_LINKS" | grep -oE 'trojan://[^ ]+')
echo "  VLESS: $VLESS_URI" | tee -a "$LOGFILE"
echo "  VMESS: $VMESS_URI" | tee -a "$LOGFILE"
echo "  Trojan: $TROJAN_URI" | tee -a "$LOGFILE"

# 解析并打印关键连接参数：UUID、端口、SNI、Host、传输类型等
UUID=$(echo "$VLESS_URI" | grep -oP '(?<=://)[^@]+')
PORT_NUM=$(echo "$VLESS_URI" | awk -F'[@:]' '{print $3}' | cut -d'?' -f1)
SNI=$(echo "$VLESS_URI" | grep -oP '(?<=&sni=)[^&]+')
HOST=$(echo "$VLESS_URI" | grep -oP '(?<=&host=)[^&]+')
NET_TYPE=$(echo "$VLESS_URI" | grep -oP '(?<=&type=)[^&]+')
echo -e "${GREEN}连接参数:${NC}" | tee -a "$LOGFILE"
echo "  UUID: $UUID" | tee -a "$LOGFILE"
echo "  端口: $PORT_NUM" | tee -a "$LOGFILE"
echo "  SNI: $SNI" | tee -a "$LOGFILE"
echo "  Host: $HOST" | tee -a "$LOGFILE"
echo "  传输类型: $NET_TYPE" | tee -a "$LOGFILE"

echo -e "${GREEN}>>> 部署完成，服务已启动并运行。${NC}" | tee -a "$LOGFI
