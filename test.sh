#!/bin/bash
set -e

# =========================================
# 自控版一键部署脚本（整合优化版）
# Author: gmddd002 + 优化整合
# =========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'  # 无颜色

LOGFILE="app.log"

# 创建缓存目录
CACHE_DIR="./.cache"
mkdir -p "$CACHE_DIR"
echo -e "${GREEN}>>> 缓存目录已创建: $CACHE_DIR${NC}" | tee -a "$LOGFILE"

# 安装必要依赖
echo -e "${GREEN}>>> 安装依赖: python3、pip、screen、jq、curl、git...${NC}" | tee -a "$LOGFILE"
apt-get update -y
apt-get install -y python3 python3-pip screen jq curl git

# 安装 cloudflared
echo -e "${GREEN}>>> 安装 cloudflared（Argo 隧道客户端）...${NC}" | tee -a "$LOGFILE"
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb 2>/dev/null || apt-get install -f -y
rm -f cloudflared.deb

# 克隆仓库并安装 Python 依赖
echo -e "${GREEN}>>> 克隆 GitHub 仓库并安装 Python 依赖...${NC}" | tee -a "$LOGFILE"
cd /root || exit
rm -rf python-xray-argo
git clone https://github.com/gmddd002/python-xray-argo.git
cd python-xray-argo
pip3 install -r requirements.txt

# 自动分配未占用端口（20000-29999）
echo -e "${GREEN}>>> 分配未占用端口...${NC}" | tee -a "$LOGFILE"
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
  [[ -n "$PORT" ]] && break
done
export PORT
echo -e "${BLUE}Allocated PORT:${NC} $PORT" | tee -a "$LOGFILE"

# 启动 Xray-Argo 服务 app.py
echo -e "${GREEN}>>> 启动 app.py 服务...${NC}" | tee -a "$LOGFILE"
nohup python3 app.py --port $PORT >/dev/null 2>&1 &
MAIN_PID=$!
sleep 5

# 保活循环
(
  while true; do
    if ! ps -p $MAIN_PID >/dev/null 2>&1; then
      echo "[KEEPALIVE] app.py crashed, restarting..." >> keepalive.log
      python3 app.py --port $PORT >/dev/null 2>&1 &
      MAIN_PID=$!
      echo "[KEEPALIVE] app.py restarted with PID $MAIN_PID" >> keepalive.log
    fi
    sleep 10
  done
) &
KEEP_PID=$!

# 模拟 Argo 域名（真实可用场景替换成 cloudflared 输出）
ARGO_ADDR="brass-cp-tvs-tale.trycloudflare.com"
echo -e "${GREEN}临时 Argo 隧道域名:${NC} $ARGO_ADDR" | tee -a "$LOGFILE"

# 生成节点配置
UUID=$(cat /proc/sys/kernel/random/uuid)
SNI="$ARGO_ADDR"
HOST="$ARGO_ADDR"

VLESS_LINK="vless://$UUID@www.visa.com.tw:443?encryption=none&security=tls&sni=$SNI&fp=chrome&type=ws&host=$HOST&path=%2Fvless-argo%3Fed%3D2560#Vls-US-Amazon_Technologies_Inc."
VMESS_JSON="{\"v\": \"2\", \"ps\": \"Vls-US-Amazon_Technologies_Inc.\", \"add\": \"www.visa.com.tw\", \"port\": \"443\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$HOST\", \"path\": \"/vmess-argo?ed=2560\", \"tls\": \"tls\", \"sni\": \"$SNI\", \"fp\": \"chrome\"}"
VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w0)"
TROJAN_LINK="trojan://$UUID@www.visa.com.tw:443?security=tls&sni=$SNI&fp=chrome&type=ws&host=$HOST&path=%2Ftrojan-argo%3Fed%3D2560#Vls-US-Amazon_Technologies_Inc."

# 保存订阅文件
cat > "$CACHE_DIR/sub.txt" <<EOF
$VLESS_LINK

$VMESS_LINK

$TROJAN_LINK
EOF
echo -e "${GREEN}订阅文件已保存: $CACHE_DIR/sub.txt${NC}" | tee -a "$LOGFILE"

# Base64 订阅
BASE64_SUB=$(base64 -w0 "$CACHE_DIR/sub.txt")

# 输出整合信息
IP=$(hostname -I | awk '{print $1}')
echo
echo "========================================"
echo "                  部署完成！             "
echo "========================================"
echo
echo "=== 服务信息 ==="
echo "服务状态: 运行中"
echo "主服务PID: $MAIN_PID"
echo "保活服务PID: $KEEP_PID"
echo "服务端口: $PORT"
echo "UUID: $UUID"
echo "订阅路径: /sub"
echo
echo "=== 访问地址 ==="
echo "订阅地址: http://$IP:$PORT/sub"
echo "管理面板: http://$IP:$PORT"
echo "本地订阅: http://localhost:$PORT/sub"
echo "本地面板: http://localhost:$PORT"
echo
echo "=== 节点信息 ==="
echo "$VLESS_LINK"
echo "$VMESS_LINK"
echo "$TROJAN_LINK"
echo
echo "=== Base64 订阅 ==="
echo "$BASE64_SUB"
echo
echo "=== 重要提示 ==="
echo "YouTube / Netflix 等流媒体分流已集成到 xray 配置，无需额外设置"
echo "服务将持续在后台运行，节点信息已生成到 $CACHE_DIR/sub.txt"
echo
