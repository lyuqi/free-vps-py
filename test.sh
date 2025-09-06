#!/bin/bash
# =========================================
# 自控版一键部署脚本 (无 root 兼容 + 完整输出版)
# Author: gmddd002
# Repo: https://github.com/gmddd002/free-vps-py
# Project: https://github.com/gmddd002/python-xray-argo
# =========================================

set -e
LOGFILE="deploy.log"
echo ">>> 开始部署（无 root 环境兼容版）..." | tee -a "$LOGFILE"

# ================================
# 1. Python 环境 & 依赖
# ================================
echo ">>> 安装 Python 依赖..." | tee -a "$LOGFILE"
pip3 install --user --upgrade pip requests psutil > /dev/null 2>&1 || true

# ================================
# 2. cloudflared (Argo Tunnel)
# ================================
echo ">>> 下载 cloudflared..." | tee -a "$LOGFILE"
mkdir -p ~/.local/bin
CLOUDFLARED=~/.local/bin/cloudflared
curl -L -o "$CLOUDFLARED" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x "$CLOUDFLARED"
export PATH="$HOME/.local/bin:$PATH"

# ================================
# 3. 拉取用户仓库
# ================================
rm -rf ~/python-xray-argo
git clone https://github.com/gmddd002/python-xray-argo.git ~/python-xray-argo
cd ~/python-xray-argo
pip3 install --user -r requirements.txt > /dev/null 2>&1 || true

# ================================
# 4. 分配随机端口
# ================================
PORT=$(python3 - <<'PYCODE'
import socket, random
while True:
    port = random.randint(20000, 29999)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        if s.connect_ex(('127.0.0.1', port)) != 0:
            print(port)
            break
PYCODE
)
export PORT

# ================================
# 5. 启动服务
# ================================
echo ">>> 启动 Xray-Argo 应用..." | tee -a "$LOGFILE"
nohup python3 app.py > app.log 2>&1 &
MAIN_PID=$!
# 保活
nohup bash -c "while true; do ps -p $MAIN_PID >/dev/null || nohup python3 app.py > app.log 2>&1 &; sleep 30; done" >/dev/null 2>&1 &
KEEP_PID=$!

# ================================
# 6. 等待节点信息生成
# ================================
SUB_FILE="sub.txt"
for i in {1..30}; do
    if [ -s "$SUB_FILE" ]; then
        break
    fi
    sleep 2
done

SUB_B64=$(cat "$SUB_FILE" 2>/dev/null || echo "")
DECODED_LINKS=$(echo "$SUB_B64" | base64 -d 2>/dev/null || echo "")

VLESS_URI=$(echo "$DECODED_LINKS" | grep -m1 '^vless://')
VMESS_URI=$(echo "$DECODED_LINKS" | grep -m1 '^vmess://')
TROJAN_URI=$(echo "$DECODED_LINKS" | grep -m1 '^trojan://')

UUID=$(echo "$VLESS_URI" | grep -oP '(?<=://)[^@]+')
SNI=$(echo "$VLESS_URI" | grep -oP '(?<=sni=)[^&]+')
HOST=$(echo "$VLESS_URI" | grep -oP '(?<=host=)[^&]+')

# ================================
# 7. 输出最终信息
# ================================
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
echo "订阅地址: http://$(curl -s ifconfig.me):$PORT/sub"
echo "管理面板: http://$(curl -s ifconfig.me):$PORT"
echo "本地订阅: http://localhost:$PORT/sub"
echo "本地面板: http://localhost:$PORT"
echo
echo "=== 节点信息 ==="
echo "节点配置:"
[ -n "$VLESS_URI" ] && echo -e "\n$VLESS_URI\n"
[ -n "$VMESS_URI" ] && echo -e "$VMESS_URI\n"
[ -n "$TROJAN_URI" ] && echo -e "$TROJAN_URI\n"
echo
echo "订阅链接:"
echo "$SUB_B64"
echo
cat > ~/.xray_nodes_info <<EOF
服务端口: $PORT
UUID: $UUID
订阅: http://$(curl -s ifconfig.me):$PORT/sub

$VLESS_URI
$VMESS_URI
$TROJAN_URI
EOF

echo "节点信息已保存到 ~/.xray_nodes_info"
echo "=== 重要提示 ==="
echo "部署已完成，节点信息已成功生成"
echo "可以立即使用订阅地址导入客户端"
echo "已集成 YouTube/Netflix/Disney/PrimeVideo 分流规则"
echo "服务将持续在后台运行"
echo
echo "部署完成！感谢使用！"
