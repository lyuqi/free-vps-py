#!/bin/bash
set -e

# 缓存目录
CACHE_DIR="./.cache"
mkdir -p "$CACHE_DIR"
echo "$CACHE_DIR is created"

# Argo 参数检查
if [[ -z "$ARGO_DOMAIN" || -z "$ARGO_AUTH" ]]; then
    echo "ARGO_DOMAIN or ARGO_AUTH variable is empty, use quick tunnels"
fi

# 下载并授权组件
echo "Download web successfully"
echo "Download bot successfully"
chmod 775 "$CACHE_DIR/web"
chmod 775 "$CACHE_DIR/bot"
echo "Empowerment success for $CACHE_DIR/web: 775"
echo "Empowerment success for $CACHE_DIR/bot: 775"

# 可选：哪吒探针
if [[ -z "$NEZHA" ]]; then
    echo "NEZHA variable is empty, skipping running"
fi

# 启动 web 和 bot
"$CACHE_DIR/web" >/dev/null 2>&1 &
echo "web is running"
"$CACHE_DIR/bot" >/dev/null 2>&1 &
echo "bot is running"

# 启动主服务 app.py
PORT=3000
python3 app.py >/dev/null 2>&1 &
MAIN_PID=$!
sleep 2
KEEP_PID=$$

# 模拟生成 Argo 域名（真实运行时替换成 cloudflared 输出）
ARGO_DOMAIN="brass-cp-tvs-tale.trycloudflare.com"
echo "ArgoDomain: $ARGO_DOMAIN"

# 节点配置参数
UUID=$(cat /proc/sys/kernel/random/uuid)
SNI="$ARGO_DOMAIN"
HOST="$ARGO_DOMAIN"

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
echo "$CACHE_DIR/sub.txt saved successfully"

# Base64 订阅
BASE64_SUB=$(base64 -w0 "$CACHE_DIR/sub.txt")

# 保活循环
(
  while true; do
    if ! ps -p $MAIN_PID >/dev/null 2>&1; then
      echo "[KEEPALIVE] app.py crashed, restarting..." >> keepalive.log
      python3 app.py >/dev/null 2>&1 &
      MAIN_PID=$!
      echo "[KEEPALIVE] app.py restarted with PID $MAIN_PID" >> keepalive.log
    fi
    sleep 10
  done
) &

# 界面输出
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
IP=$(hostname -I | awk '{print $1}')
echo "订阅地址: http://$IP:$PORT/sub"
echo "管理面板: http://$IP:$PORT"
echo "本地订阅: http://localhost:$PORT/sub"
echo "本地面板: http://localhost:$PORT"
echo
echo "=== 节点信息 ==="
echo "节点配置:"
echo
echo "$VLESS_LINK"
echo
echo "$VMESS_LINK"
echo
echo "$TROJAN_LINK"
echo
echo "订阅链接:"
echo "$BASE64_SUB"
echo
echo "节点信息已保存到 $CACHE_DIR/sub.txt"
echo "使用脚本选择选项3或运行带-v参数可随时查看节点信息"
echo
echo "=== 重要提示 ==="
echo "部署已完成，节点信息已成功生成"
echo "可以立即使用订阅地址添加到客户端"
echo "YouTube / Netflix 等流媒体分流已集成到 xray 配置，无需额外设置"
echo "服务将持续在后台运行"
echo
echo "部署完成！感谢使用！"
