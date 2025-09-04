#!/usr/bin/env bash
# test_fixed_full.sh
# 完整版：闭环部署 + 内嵌守护 + 流媒体分流优化 + 输出模板化
# Author: gmddd002 (adapted)
set -euo pipefail
IFS=$'\n\t'

######################
# 配置 - 如有需要可修改
######################
GIT_REPO="https://github.com/gmddd002/python-xray-argo.git"
WORKDIR="$HOME/app"
PROJECT_DIR="$WORKDIR/python-xray-argo"
CACHE_DIR="$PROJECT_DIR/.cache"
SUB_FILE="$CACHE_DIR/sub.txt"
LOGFILE="$PROJECT_DIR/app.log"
KEEPALIVE_LOG="$PROJECT_DIR/keepalive.log"
NODE_INFO="$HOME/.xray_nodes_info"
PORT_MIN=20000
PORT_MAX=29999
KEEP_INTERVAL=10   # 秒，守护检查间隔
SUB_WAIT_TIMEOUT=60  # 秒（等待 .cache/sub.txt 的最长时间）

######################
# 简单输出颜色
######################
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${GREEN}>>> 开始部署（闭环版）...${NC}"

# 确认依赖，并安装缺失项（在容器里通常可用）
if ! command -v git >/dev/null 2>&1; then
  echo -e "${BLUE}安装 git...${NC}"
  sudo apt-get update
  sudo apt-get install -y git
fi
for pkg in python3 python3-pip curl jq; do
  if ! command -v "$(basename $pkg)" >/dev/null 2>&1 && ! dpkg -s "$pkg" >/dev/null 2>&1; then
    echo -e "${BLUE}安装 $pkg ...${NC}"
    sudo apt-get install -y $pkg || true
  fi
done

# cloudflared 安装（如果不存在则尝试安装）
if ! command -v cloudflared >/dev/null 2>&1; then
  echo -e "${BLUE}安装 cloudflared（Argo 客户端）...${NC}"
  tmpdeb="$(mktemp)"
  curl -fsSL -o "$tmpdeb" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" || true
  if [[ -s "$tmpdeb" ]]; then
    sudo dpkg -i "$tmpdeb" 2>/dev/null || sudo apt-get install -f -y
    rm -f "$tmpdeb"
  else
    echo -e "${RED}警告：无法下载安装 cloudflared（网络或权限问题），继续但 Argo 功能可能受限${NC}"
    rm -f "$tmpdeb"
  fi
fi

# 准备工作目录
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# clone 或 pull 你的项目（完全闭环）
if [[ -d "$PROJECT_DIR" ]]; then
  echo -e "${GREEN}更新项目仓库...${NC}"
  cd "$PROJECT_DIR"
  git pull --rebase || git reset --hard origin/main || true
else
  echo -e "${GREEN}克隆项目仓库...${NC}"
  git clone "$GIT_REPO" "$PROJECT_DIR"
  cd "$PROJECT_DIR"
fi

# 安装 Python 依赖（如果存在 requirements.txt）
if [[ -f "requirements.txt" ]]; then
  echo -e "${GREEN}安装 Python 依赖...${NC}"
  pip3 install -r requirements.txt --no-cache-dir || true
fi

# 如果项目有自带脚本需要可执行权限，给它们权限
chmod -R a+x "$PROJECT_DIR" || true

# 分配随机可用端口（20000-29999）
echo -e "${GREEN}>>> 分配未占用端口...${NC}"
get_free_port() {
  python3 - <<PYCODE
import socket,random
for _ in range(200):
    p=random.randint($PORT_MIN,$PORT_MAX)
    s=socket.socket()
    try:
        s.bind(('127.0.0.1',p))
        s.close()
        print(p)
        break
    except:
        pass
PYCODE
}
PORT="$(get_free_port)"
if [[ -z "$PORT" ]]; then
  echo -e "${RED}无法分配端口，退出${NC}"
  exit 1
fi
export PORT
echo -e "${BLUE}Allocated PORT:${NC} $PORT"

# 启动 app.py（用 nohup + tee 记录日志）
echo -e "${GREEN}>>> 启动主服务 app.py（日志：$LOGFILE）...${NC}"
# 先杀掉旧进程（若有）
pkill -f "python3 .*app.py" >/dev/null 2>&1 || true
nohup python3 app.py 2>&1 | tee -a "$LOGFILE" >/dev/null &
MAIN_PID=$!
sleep 3

# 启动 web/bot 或其它脚本（如果项目中存在启动脚本）
# （保留原仓库习惯，这里尝试启动 ./web ./bot 如果存在）
if [[ -x "./web" ]]; then
  nohup ./web >/dev/null 2>&1 &
  echo -e "${GREEN}web is running${NC}"
fi
if [[ -x "./bot" ]]; then
  nohup ./bot >/dev/null 2>&1 &
  echo -e "${GREEN}bot is running${NC}"
fi

# 备份原来的 config.json（若存在）并插入流媒体分流规则（版本B：geosite -> direct）
CONFIG_JSON="$PROJECT_DIR/config.json"
BACKUP_CONFIG="$PROJECT_DIR/config.json.bak.$(date +%s)"
if [[ -f "$CONFIG_JSON" ]]; then
  echo -e "${GREEN}备份并合并 Xray 配置，插入流媒体分流规则...${NC}"
  cp "$CONFIG_JSON" "$BACKUP_CONFIG"
  # 使用 jq 合并 routing.rules，若 jq 不在，简单替换（保守）
  if command -v jq >/dev/null 2>&1; then
    # create rules array snippet
    read -r -d '' RULES_JSON <<'JSON' || true
[
  {"type":"field","domain":["geosite:youtube","geosite:netflix","geosite:primevideo","geosite:disney","geosite:hulu","geosite:spotify"],"outboundTag":"direct"},
  {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"}
]
JSON
    # merge rules: append RULES_JSON into existing routing.rules if present
    tmpcfg="$(mktemp)"
    jq --argjson addrules "$RULES_JSON" '
      if (.routing and .routing.rules) then
        .routing.rules = (.routing.rules + $addrules)
      elif (.routing and (.routing.rules|not)) then
        .routing.rules = $addrules
      else
        .routing = { "rules": $addrules }
      end' "$CONFIG_JSON" > "$tmpcfg" && mv "$tmpcfg" "$CONFIG_JSON"
  else
    # fallback: append a routing section at end (may be override by app)
    cat >> "$CONFIG_JSON" <<EOF

, "routing_added_by_script": true
EOF
    echo -e "${RED}注意：系统中未安装 jq，已做简易修改，但建议安装 jq 以保证正确合并配置。${NC}"
  fi
else
  # 如果没有 config.json，生成一个最小 config.json 带 routing rules（不会覆盖 app.py 逻辑）
  echo -e "${GREEN}未发现 config.json，生成最小 config.json 含流媒体分流规则...${NC}"
  cat > "$CONFIG_JSON" <<'JSON'
{
  "log": { "access": "", "error": "", "loglevel": "warning" },
  "inbounds": [],
  "outbounds": [
    { "protocol": "freedom", "settings": {} },
    { "protocol": "blackhole", "settings": {} }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type":"field","domain":["geosite:youtube","geosite:netflix","geosite:primevideo","geosite:disney","geosite:hulu","geosite:spotify"],"outboundTag":"direct"},
      {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"}
    ]
  }
}
JSON
fi

# 等待订阅文件生成（./.cache/sub.txt），最长等待 SUB_WAIT_TIMEOUT 秒
echo -e "${GREEN}等待生成订阅文件（$SUB_FILE）...${NC}"
wait_count=0
while [[ ! -f "$SUB_FILE" && $wait_count -lt $SUB_WAIT_TIMEOUT ]]; do
  sleep 1
  wait_count=$((wait_count + 1))
done

# 如果存在 .cache/sub.txt 就读取，否则尝试从 app.log 中提取 Base64 订阅
SUB_B64=""
if [[ -f "$SUB_FILE" ]]; then
  SUB_B64="$(cat "$SUB_FILE" 2>/dev/null || echo "")"
else
  # 从日志中抽取 base64 订阅（有些版本会直接输出）
  SUB_B64="$(grep -oE '[A-Za-z0-9+/=]{200,}' "$LOGFILE" | head -n1 || true)"
fi

# 解码订阅（如果有）
DECODED_LINKS=""
if [[ -n "$SUB_B64" ]]; then
  # 确保 base64 没换行
  echo "$SUB_B64" > "$PROJECT_DIR/.last_sub_b64.txt"
  DECODED_LINKS="$(base64 -d "$PROJECT_DIR/.last_sub_b64.txt" 2>/dev/null || true)"
fi

# 解析节点 URI（vless/vmess/trojan）
VLESS_URI="$(echo "$DECODED_LINKS" | grep -oE 'vless://[^[:space:]]+' || true)"
VMESS_URI="$(echo "$DECODED_LINKS" | grep -oE 'vmess://[^[:space:]]+' || true)"
TROJAN_URI="$(echo "$DECODED_LINKS" | grep -oE 'trojan://[^[:space:]]+' || true)"

# 解析 VLESS 的 UUID / 端口 / sni / host / type（严格匹配 UUID）
UUID=""
if [[ -n "$VLESS_URI" ]]; then
  UUID="$(echo "$VLESS_URI" | grep -oP '(?<=vless://)[0-9a-fA-F\-]{36}' || true)"
fi
PORT_NUM="$PORT"
if [[ -n "$VLESS_URI" ]]; then
  # attempt to get port from VLESS (if different)
  ptmp="$(echo "$VLESS_URI" | awk -F'[@:]' '{print $3}' | cut -d'?' -f1 || true)"
  if [[ -n "$ptmp" && "$ptmp" =~ ^[0-9]+$ ]]; then PORT_NUM="$ptmp"; fi
fi
SNI="$(echo "$VLESS_URI" | grep -oP '(?<=[&?]sni=)[^&]+' || true)"
HOST="$(echo "$VLESS_URI" | grep -oP '(?<=[&?]host=)[^&]+' || true)"
NET_TYPE="$(echo "$VLESS_URI" | grep -oP '(?<=[&?]type=)[^&]+' || true)"

# 保活守护（内嵌），写入 keepalive.log
cat > "$PROJECT_DIR/.daemon_keepalive.sh" <<'SH'
#!/usr/bin/env bash
set -e
MAIN_PID_PLACEHOLDER=$MAIN_PID_PLACEHOLDER
APP_LOG="$LOGFILE_PLACEHOLDER"
KEEP_LOG="$KEEPALIVE_LOG_PLACEHOLDER"
INTERVAL=$KEEP_INTERVAL_PLACEHOLDER
PROJECT_DIR="$PROJECT_DIR_PLACEHOLDER"

while true; do
  # check if app.py is running
  if ! ps -p $MAIN_PID_PLACEHOLDER >/dev/null 2>&1; then
    echo "[$(date '+%F %T')] app.py not running, starting..." >> "$KEEP_LOG"
    cd "$PROJECT_DIR"
    nohup python3 app.py 2>&1 | tee -a "$APP_LOG" >/dev/null &
    NEWPID=$!
    echo "[$(date '+%F %T')] restarted app.py, pid=$NEWPID" >> "$KEEP_LOG"
    MAIN_PID_PLACEHOLDER=$NEWPID
  fi
  sleep $INTERVAL
done
SH

# substitute placeholders
sed -i "s|MAIN_PID_PLACEHOLDER|$MAIN_PID|g" "$PROJECT_DIR/.daemon_keepalive.sh"
sed -i "s|APP_LOG_PLACEHOLDER|$LOGFILE|g" "$PROJECT_DIR/.daemon_keepalive.sh"
sed -i "s|KEEPALIVE_LOG_PLACEHOLDER|$KEEPALIVE_LOG|g" "$PROJECT_DIR/.daemon_keepalive.sh"
sed -i "s|KEEP_INTERVAL_PLACEHOLDER|$KEEP_INTERVAL|g" "$PROJECT_DIR/.daemon_keepalive.sh"
sed -i "s|PROJECT_DIR_PLACEHOLDER|$PROJECT_DIR|g" "$PROJECT_DIR/.daemon_keepalive.sh"
chmod +x "$PROJECT_DIR/.daemon_keepalive.sh"
# 启动守护（后台）
nohup bash "$PROJECT_DIR/.daemon_keepalive.sh" >/dev/null 2>&1 &
KEEPER_PID=$!

# 获取主机公网IP（尽量）
PUBLIC_IP="$(curl -s --max-time 3 https://ipv4.icanhazip.com || hostname -I | awk '{print $1}' || echo "0.0.0.0')"

# 保存节点信息到文件
cat > "$NODE_INFO" <<EOF
=======================================
           节点信息保存
=======================================
部署时间: $(date)
主服务PID: $MAIN_PID
保活PID: $KEEPER_PID
服务端口: $PORT_NUM
UUID: ${UUID:-(unknown)}
订阅路径: /sub
订阅文件: ${SUB_FILE}
EOF

# 格式化输出（模仿对方）
echo "========================================"
echo "                      部署完成！                      "
echo "========================================"
echo
echo "=== 服务信息 ==="
echo "服务状态: 运行中"
echo "主服务PID: $MAIN_PID"
echo "保活服务PID: $KEEPER_PID"
echo "服务端口: "
echo "$PORT_NUM"
echo "UUID: ${UUID:-UUID}"
echo "订阅路径: /sub"
echo
echo "=== 访问地址 ==="
echo "订阅地址: http://$PUBLIC_IP:$PORT_NUM/sub"
echo "管理面板: http://$PUBLIC_IP:$PORT_NUM"
echo "本地订阅: http://localhost:$PORT_NUM/sub"
echo "本地面板: http://localhost:$PORT_NUM"
echo
echo "=== 节点信息 ==="
echo "节点配置:"
echo
if [[ -n "$VLESS_URI" ]]; then echo "$VLESS_URI"; else echo "(VLESS not found)"; fi
echo
if [[ -n "$VMESS_URI" ]]; then echo "$VMESS_URI"; else echo "(VMESS not found)"; fi
echo
if [[ -n "$TROJAN_URI" ]]; then echo "$TROJAN_URI"; else echo "(TROJAN not found)"; fi
echo
echo
echo "订阅链接:"
if [[ -n "$SUB_B64" ]]; then
  echo "$SUB_B64"
else
  echo "(订阅未生成或无法提取)"
fi
echo
echo "节点信息已保存到 $NODE_INFO"
echo "使用脚本选择选项3或运行带 -v 参数可随时查看节点信息"
echo "=== 重要提示 ==="
echo "部署已完成，节点信息已成功生成"
echo "可以立即使用订阅地址添加到客户端"
echo "YouTube/Netflix 等主流流媒体分流已集成到 xray 配置（direct/freedom），如需改为代理请在 config.json 修改 outboundTag"
echo "服务将持续在后台运行"
echo
echo "部署完成！感谢使用！"

# 结束
exit 0
