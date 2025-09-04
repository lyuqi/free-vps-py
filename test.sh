#!/bin/bash
# =========================================
# Xray + Argo 一键部署脚本（无 root 兼容版）
# Author: gmddd002 (优化版)
# =========================================

set -e
LOGFILE="app.log"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}>>> 开始部署（无 root 环境兼容版）...${NC}"

# 1. 安装 Python 依赖
echo -e "${GREEN}>>> 安装 Python 依赖...${NC}"
pip install --upgrade pip >/dev/null 2>&1 || true
pip install requests psutil >/dev/null 2>&1 || true

# 2. 下载 cloudflared
echo -e "${GREEN}>>> 下载 cloudflared...${NC}"
curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared

# 3. 克隆项目并安装依赖
if [ ! -d "python-xray-argo" ]; then
  git clone https://github.com/gmddd002/python-xray-argo.git
fi
cd python-xray-argo
pip install -r requirements.txt >/dev/null 2>&1

# 4. 随机端口
PORT=$(python3 - <<'PYCODE'
import socket,random
while True:
    p=random.randint(20000,29999)
    with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as s:
        if s.connect_ex(('127.0.0.1',p))!=0:
            print(p);break
PYCODE
)

# 5. 启动 app.py
echo -e "${GREEN}>>> 启动 Xray-Argo 应用...${NC}"
nohup python3 app.py >../$LOGFILE 2>&1 &
MAIN_PID=$!
sleep 12

# 6. 启动保活进程
nohup bash -c "while true; do if ! ps -p $MAIN_PID > /dev/null; then python3 app.py >>../$LOGFILE 2>&1 & fi; sleep 15; done" >/dev/null 2>&1 &
KEEP_PID=$!

# 7. 提取 Argo 域名
ARGO_ADDR=$(grep -hoE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' ../$LOGFILE boot.log nohup.out 2>/dev/null | head -n1)
ARGO_ADDR=${ARGO_ADDR#https://}

# 8. 读取订阅
if [ -f ".cache/sub.txt" ]; then
    SUB_B64=$(cat .cache/sub.txt)
elif [ -f "sub.txt" ]; then
    SUB_B64=$(cat sub.txt)
else
    SUB_B64=""
fi

if [ -n "$SUB_B64" ]; then
    DECODED=$(echo "$SUB_B64" | base64 -d 2>/dev/null || echo "")
else
    DECODED=""
fi

# 9. 节点信息
VLESS_URI=$(echo "$DECODED" | grep -oE 'vless://[^ ]+' | head -n1)
VMESS_URI=$(echo "$DECODED" | grep -oE 'vmess://[^ ]+' | head -n1)
TROJAN_URI=$(echo "$DECODED" | grep -oE 'trojan://[^ ]+' | head -n1)

UUID=$(echo "$VLESS_URI" | grep -oP '(?<=vless://)[0-9a-fA-F-]{36}')
PORT_NUM=$(echo "$VLESS_URI" | awk -F'[@:]' '{print $3}' | cut -d'?' -f1)
SNI=$(echo "$VLESS_URI" | grep -oP '(?<=sni=)[^&]+')
HOST=$(echo "$VLESS_URI" | grep -oP '(?<=host=)[^&]+')
NET_TYPE=$(echo "$VLESS_URI" | grep -oP '(?<=type=)[^&]+')

# 10. 保存节点
INFO_FILE="/home/$(whoami)/.xray_nodes_info"
cat > $INFO_FILE <<EOF
=== 节点信息 ===
VLESS: $VLESS_URI
VMESS: $VMESS_URI
Trojan: $TROJAN_URI

订阅链接:
$SUB_B64

连接参数:
UUID: $UUID
端口: $PORT_NUM
SNI: $SNI
Host: $HOST
传输类型: $NET_TYPE
EOF

# 11. 输出结果
echo -e "${BLUE}========================================${NC}"
echo -e "                  部署完成！             "
echo -e "${BLUE}========================================${NC}\n"

echo "=== 服务信息 ==="
echo "服务状态: 运行中"
echo "主服务PID: $MAIN_PID"
echo "保活服务PID: $KEEP_PID"
echo "服务端口: $PORT"
echo "UUID: $UUID"
echo "订阅路径: /sub"
echo
echo "=== 访问地址 ==="
echo "订阅地址: http://$ARGO_ADDR:$PORT/sub"
echo "管理面板: http://$ARGO_ADDR:$PORT"
echo "本地订阅: http://localhost:$PORT/sub"
echo "本地面板: http://localhost:$PORT"
echo
echo "=== 节点信息 ==="
echo "VLESS: $VLESS_URI"
echo "VMESS: $VMESS_URI"
echo "Trojan: $TROJAN_URI"
echo
echo "订阅链接:"
echo "$SUB_B64"
echo
echo "节点信息已保存到 $INFO_FILE"
echo "=== 重要提示 ==="
echo "已集成 YouTube/Netflix/Disney/PrimeVideo 分流规则"
echo "服务将持续在后台运行"
echo
echo "部署完成！感谢使用！"
