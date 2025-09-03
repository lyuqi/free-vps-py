#!/bin/bash
# =========================================
# 一键部署 Xray-Argo + Cloudflared 隧道
# Author: 改写整合版
# =========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

LOGFILE="app.log"

echo -e "${GREEN}>>> 更新软件源并安装必要依赖...${NC}" | tee -a "$LOGFILE"
apt-get update
apt-get install -y python3 python3-pip screen jq curl git

echo -e "${GREEN}>>> 安装 cloudflared（Argo 隧道客户端）...${NC}" | tee -a "$LOGFILE"
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb 2>/dev/null || apt-get install -f -y
rm -f cloudflared.deb

echo -e "${GREEN}>>> 克隆用户仓库并安装 Python 依赖...${NC}" | tee -a "$LOGFILE"
cd /root || exit
rm -rf python-xray-argo
git clone https://github.com/gmddd002/python-xray-argo.git
cd python-xray-argo || exit
pip3 install -r requirements.txt

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
    if [[ -n "$PORT" ]]; then break; fi
done
export PORT
echo -e "${BLUE}Allocated PORT:$NC $PORT" | tee -a "$LOGFILE"

echo -e "${GREEN}>>> 启动 Xray-Argo 应用 (app.py)...${NC}" | tee -a "$LOGFILE"
# 后台运行服务并记录日志
nohup python3 app.py 2>&1 | tee -a "$LOGFILE" &

# 等待服务生成 boot.log
echo -e "${GREEN}>>> 等待服务启动并生成 boot.log ...${NC}" | tee -a "$LOGFILE"
while [ ! -f boot.log ]; do sleep 2; done
sleep 5 # 额外等待确保服务完全启动

# 提取 Argo Tunnel 临时域名
ARGO_ADDR=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' boot.log | head -n1)
ARGO_ADDR=${ARGO_ADDR#https://}
echo -e "${GREEN}临时隧道地址:${NC} $ARGO_ADDR" | tee -a "$LOGFILE"

# 读取 Base64 订阅
if [ -f sub.txt ]; then
    SUB_B64=$(cat sub.txt)
    echo -e "${GREEN}Base64 订阅链接:${NC} $SUB_B64" | tee -a "$LOGFILE"
    DECODED_LINKS=$(echo "$SUB_B64" | base64 -d)

    echo -e "${GREEN}节点连接信息 (VLESS/VMESS/Trojan):${NC}" | tee -a "$LOGFILE"
    VLESS_URI=$(echo "$DECODED_LINKS" | grep -oE 'vless://[^ ]+')
    VMESS_URI=$(echo "$DECODED_LINKS" | grep -oE 'vmess://[^ ]+')
    TROJAN_URI=$(echo "$DECODED_LINKS" | grep -oE 'trojan://[^ ]+')

    echo " VLESS: $VLESS_URI" | tee -a "$LOGFILE"
    echo " VMESS: $VMESS_URI" | tee -a "$LOGFILE"
    echo " Trojan: $TROJAN_URI" | tee -a "$LOGFILE"

    # 提取关键参数
    UUID=$(echo "$VLESS_URI" | grep -oP '(?<=://)[^@]+')
    PORT_NUM=$(echo "$VLESS_URI" | awk -F'[@:]' '{print $3}' | cut -d'?' -f1)
    SNI=$(echo "$VLESS_URI" | grep -oP '(?<=&sni=)[^&]+')
    HOST=$(echo "$VLESS_URI" | grep -oP '(?<=&host=)[^&]+')
    NET_TYPE=$(echo "$VLESS_URI" | grep -oP '(?<=&type=)[^&]+')

    echo -e "${GREEN}连接参数:${NC}" | tee -a "$LOGFILE"
    echo " UUID: $UUID" | tee -a "$LOGFILE"
    echo " 端口: $PORT_NUM" | tee -a "$LOGFILE"
    echo " SNI: $SNI" | tee -a "$LOGFILE"
    echo " Host: $HOST" | tee -a "$LOGFILE"
    echo " 传输类型: $NET_TYPE" | tee -a "$LOGFILE"
else
    echo -e "${RED}未找到 sub.txt，无法解析订阅${NC}" | tee -a "$LOGFILE"
fi

echo -e "${GREEN}>>> 部署完成，服务已启动并运行。${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}>>> 日志记录在 $LOGFILE${NC}"
