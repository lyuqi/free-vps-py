#!/bin/bash
# =========================================
# 保守版一键部署脚本 + Flask 前端展示
# Author: gmddd002
# Repo A: https://github.com/gmddd002/free-vps-py   (入口脚本)
# Repo B: https://github.com/gmddd002/python-xray-argo (核心逻辑)
# =========================================

set -e
BASE_DIR=$HOME/app
REPO_B="$HOME/python-xray-argo"
LOGFILE="$BASE_DIR/app.log"

mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

echo ">>> 开始部署（保守版）..."

# ========== 安装依赖 ==========
echo ">>> 安装 Python 依赖..."
pip3 install --user -U pip requests psutil flask

# ========== 安装 cloudflared ==========
echo ">>> 下载 cloudflared..."
mkdir -p "$BASE_DIR/bin"
CLOUDFLARED="$BASE_DIR/bin/cloudflared"
curl -L -o "$CLOUDFLARED" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x "$CLOUDFLARED"

# ========== 拉取仓库 B ==========
echo ">>> 拉取 python-xray-argo..."
rm -rf "$REPO_B"
git clone https://github.com/gmddd002/python-xray-argo.git "$REPO_B"
cd "$REPO_B"

echo ">>> 安装 requirements..."
pip3 install --user -r requirements.txt

# ========== 启动服务 ==========
echo ">>> 启动 Xray-Argo 应用..."
# 杀掉可能残留的旧进程
pkill -f "python3 app.py" || true

# 启动主服务
nohup python3 app.py >"$LOGFILE" 2>&1 &
MAIN_PID=$!

# 启动保活进程
(
  while true; do
    if ! ps -p $MAIN_PID > /dev/null; then
      echo ">>> [保活] 发现服务退出，重启中..." | tee -a "$LOGFILE"
      nohup python3 app.py >>"$LOGFILE" 2>&1 &
      MAIN_PID=$!
    fi
    sleep 20
  done
) &
KEEPALIVE_PID=$!

sleep 10

# ========== 展示节点信息 ==========
echo "========================================"
echo "              部署完成！"
echo "========================================"
echo
echo "=== 服务信息 ==="
echo "服务状态: 运行中"
echo "主服务PID: $MAIN_PID"
echo "保活服务PID: $KEEPALIVE_PID"

# 从 sub.txt 读取订阅信息
SUB_FILE="$REPO_B/sub.txt"
if [[ -f "$SUB_FILE" ]]; then
  SUB_B64=$(cat "$SUB_FILE")
  LINKS=$(echo "$SUB_B64" | base64 -d 2>/dev/null || true)

  echo
  echo "=== 节点信息 ==="
  echo "$LINKS"
  echo
  echo "订阅链接:"
  echo "$SUB_B64"
else
  echo
  echo "⚠️ 未找到 $SUB_FILE，节点信息暂不可用"
fi

# 保存节点信息
cat > ~/.xray_nodes_info <<EOF
=======================================
           节点信息保存
=======================================
部署时间: $(date)
主服务PID: $MAIN_PID
保活服务PID: $KEEPALIVE_PID
订阅文件: $SUB_FILE
日志文件: $LOGFILE
=======================================
EOF

echo
echo "节点信息已保存到 ~/.xray_nodes_info"
echo "部署完成！感谢使用！"

# ========== 启动 Flask 前端 ==========
FLASK_APP="$BASE_DIR/web_frontend.py"

cat > "$FLASK_APP" <<'PYCODE'
import base64
import os
from flask import Flask, render_template_string

app = Flask(__name__)

TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>节点信息面板</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
pre { background: #f4f4f4; padding: 10px; border-radius: 5px; }
h2 { color: #2c3e50; }
</style>
</head>
<body>
  <h1>节点信息面板</h1>
  {% if links %}
    <h2>VLESS / VMESS / Trojan</h2>
    <pre>{{ links }}</pre>
    <h2>订阅链接 (Base64)</h2>
    <pre>{{ sub_b64 }}</pre>
  {% else %}
    <p style="color:red;">未找到订阅信息，请检查 sub.txt</p>
  {% endif %}
</body>
</html>
"""

@app.route("/")
def index():
    sub_file = os.path.expanduser("~/python-xray-argo/sub.txt")
    if os.path.exists(sub_file):
        with open(sub_file, "r") as f:
            sub_b64 = f.read().strip()
        try:
            links = base64.b64decode(sub_b64).decode()
        except Exception:
            links = "⚠️ Base64 解码失败"
    else:
        sub_b64, links = None, None
    return render_template_string(TEMPLATE, links=links, sub_b64=sub_b64)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PYCODE

echo ">>> 启动 Flask 前端 (端口: 8080)..."
nohup python3 "$FLASK_APP" >"$BASE_DIR/web.log" 2>&1 &

echo "前端面板地址: http://<你的服务器IP>:8080"
