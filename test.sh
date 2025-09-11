#!/bin/bash
# =========================================
# 自控版一键部署脚本（最终版）
# Author: gmddd002
# 仓库1: https://github.com/gmddd002/free-vps-py
# 仓库2: https://github.com/gmddd002/python-xray-argo
# =========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOGFILE="app.log"

echo -e "${GREEN}>>> 开始部署（最终版）...${NC}" | tee -a "$LOGFILE"

# ======= 安装依赖 =======
echo -e "${GREEN}>>> 安装必要依赖...${NC}" | tee -a "$LOGFILE"
apt-get update
apt-get install -y python3 python3-pip screen jq curl git

# ======= 安装 cloudflared =======
echo -e "${GREEN}>>> 安装 cloudflared（Argo 隧道客户端）...${NC}" | tee -a "$LOGFILE"
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb 2>/dev/null || apt-get install -f -y
rm -f cloudflared.deb

# ======= 克隆仓库 =======
echo -e "${GREEN}>>> 克隆用户仓库并安装依赖...${NC}" | tee -a "$LOGFILE"
cd /root
rm -rf python-xray-argo
git clone https://github.com/gmddd002/python-xray-argo.git
cd python-xray-argo
pip3 install -r requirements.txt

# ======= 分配随机端口 =======
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
  if [[ -n "$PORT" ]]; then
    break
  fi
done
export PORT
echo -e "${BLUE}Allocated PORT:${NC} $PORT" | tee -a "$LOGFILE"

# ======= 优选 IP 设置 =======
echo -e "${YELLOW}当前优选IP: $(grep "CFIP = " app.py | cut -d"'" -f4)${NC}"
read -p "请输入优选IP/域名 (多个用逗号隔开，留空使用默认): " CFIP_INPUT
if [ -z "$CFIP_INPUT" ]; then
    CFIP_INPUT="104.26.13.229,104.16.165.90,104.17.36.89,104.19.155.123,172.64.87.150"
fi
sed -i "s|CFIP = os.environ.get('CFIP', '[^']*')|CFIP = os.environ.get('CFIP', '$CFIP_INPUT')|" app.py
echo -e "${GREEN}优选IP已设置为: $CFIP_INPUT${NC}"

# ======= 启动服务 =======
echo -e "${GREEN}>>> 启动 Xray-Argo 应用 (app.py)...${NC}" | tee -a "$LOGFILE"
nohup python3 app.py 2>&1 | tee -a "$LOGFILE" &
APP_PID=$!
echo $APP_PID > app.pid

# ======= 保活功能 =======
cat > keep_alive.sh << 'EOF'
#!/bin/bash
while true; do
  if ! pgrep -f "python3 app.py" > /dev/null; then
    echo "$(date) [警告] app.py 已退出，正在重启..." | tee -a app_restarts.log
    nohup python3 app.py >> app.log 2>&1 &
    echo $! > app.pid
  fi
  sleep 60
done
EOF
chmod +x keep_alive.sh
nohup ./keep_alive.sh >/dev/null 2>&1 &

# ======= 等待启动 =======
sleep 15

# ======= 提取隧道地址 =======
ARGO_ADDR=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' boot.log | head -n1)
ARGO_ADDR=${ARGO_ADDR#https://}
echo -e "${GREEN}临时隧道地址:${NC} $ARGO_ADDR" | tee -a "$LOGFILE"

# ======= 解码节点信息 =======
if [[ -f sub.txt ]]; then
  SUB_B64=$(cat sub.txt)
  echo -e "${GREEN}Base64 订阅链接:${NC} $SUB_B64" | tee -a "$LOGFILE"
  DECODED_LINKS=$(echo "$SUB_B64" | base64 -d)
  
  echo -e "${GREEN}=== 节点信息 (支持多组) ===${NC}" | tee -a "$LOGFILE"
  echo "$DECODED_LINKS" | grep -E '^(vless|vmess|trojan)://' | head -n 6 | while read -r line; do
    echo "$line" | tee -a "$LOGFILE"
  done
else
  echo -e "${RED}[错误] sub.txt 未生成，无法解析节点信息${NC}" | tee -a "$LOGFILE"
fi

echo -e "${GREEN}>>> 部署完成，服务已启动并运行。${NC}" | tee -a "$LOGFILE"
