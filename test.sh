#!/bin/bash
set -e

# ====== 色彩 ======
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ====== 基本文件/默认值 ======
APP_FILE="app.py"
NODE_INFO_FILE="${NODE_INFO_FILE:-$HOME/.xray_nodes_info}"
KEEP_ALIVE_HF="${KEEP_ALIVE_HF:-false}"

# ====== Cloudflare 候选 IP（示例，可按需扩展/替换） ======
# 提示：你也可以通过环境变量 CFIP_LIST 提供自定义列表，格式“ip1 ip2 ip3”
DEFAULT_IP_LIST=(104.16.0.1 104.17.0.1 104.18.0.1 104.19.0.1 104.20.0.1 172.64.0.1 172.65.0.1 172.66.0.1 172.67.0.1)

show_help() {
  echo -e "${YELLOW}用法:${NC} bash test.sh [选项]"
  echo "  -v, --view              查看节点信息"
  echo "  --set-ip <IP|auto>      设置优选 IP；auto 为自动测速选择"
  echo "  --deploy                部署（默认行为）"
  echo "  -h, --help              显示帮助"
}

auto_select_ip() {
  echo -e "${BLUE}开始自动测速优选 IP...${NC}"
  # 解析自定义列表（优先）
  if [[ -n "$CFIP_LIST" ]]; then
    # shellcheck disable=SC2206
    IP_LIST=($CFIP_LIST)
  else
    IP_LIST=("${DEFAULT_IP_LIST[@]}")
  fi

  if ! command -v ping >/dev/null 2>&1; then
    echo -e "${RED}未找到 ping 命令，无法测速。请在环境中安装 iputils/ping。${NC}"
    return 1
  fi

  BEST_IP=""
  BEST_PING=99999

  for ip in "${IP_LIST[@]}"; do
    # -c 1 发 1 个包；-W 1 超时 1 秒（BusyBox/不同发行版参数略有差异）
    ping_out=$(ping -c 1 -W 1 "$ip" 2>/dev/null || true)
    ping_time=$(echo "$ping_out" | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
    if [[ -n "$ping_time" ]]; then
      echo "测试 ${ip} 延迟: ${ping_time} ms"
      # 使用 awk 比较浮点
      better=$(awk -v a="$ping_time" -v b="$BEST_PING" 'BEGIN{print (a<b)?"1":"0"}')
      if [[ "$better" == "1" ]]; then
        BEST_PING="$ping_time"
        BEST_IP="$ip"
      fi
    fi
  done

  if [[ -z "$BEST_IP" ]]; then
    echo -e "${RED}未找到可用 IP，自动测速失败${NC}"
    return 1
  fi

  echo -e "${GREEN}优选 IP: $BEST_IP (延迟 ${BEST_PING}ms)${NC}"
  set_cfip_in_app "$BEST_IP"
  echo "Preferred_IP=$BEST_IP" >> "$NODE_INFO_FILE"
}

set_cfip_in_app() {
  local value="$1"
  if [[ ! -f "$APP_FILE" ]]; then
    echo -e "${RED}未找到 ${APP_FILE}，无法写入 CFIP${NC}"
    return 1
  fi
  # 仅替换默认值，不覆盖已设置的环境变量逻辑
  # 将 CFIP = os.environ.get('CFIP', 'xxx') 的默认部分改为 value
  if grep -q "CFIP = os.environ.get('CFIP'," "$APP_FILE"; then
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '${value//\//\\/}')/" "$APP_FILE"
    echo -e "${GREEN}已将 ${APP_FILE} 中 CFIP 默认值设置为: $value${NC}"
  else
    echo -e "${YELLOW}未检测到标准写法“CFIP = os.environ.get('CFIP', ...)”，请确认 app.py 实现${NC}"
  fi
}

maybe_start_keepalive() {
  if [[ "$KEEP_ALIVE_HF" != "true" ]]; then
    return 0
  fi
  if [[ -z "$HF_TOKEN" || -z "$SPACE_ID" ]]; then
    echo -e "${YELLOW}KEEP_ALIVE_HF=true，但未设置 HF_TOKEN 或 SPACE_ID，跳过保活${NC}"
    return 0
  fi
  cat > keep_alive_task.sh <<'EOF'
#!/bin/bash
: "${HF_TOKEN:?missing}"
: "${SPACE_ID:?missing}"
while true; do
  curl -s -H "Authorization: Bearer $HF_TOKEN" \
       -X POST "https://huggingface.co/api/spaces/${SPACE_ID}/runtime/ping" \
       -o /dev/null || true
  sleep 120
done
EOF
  chmod 700 keep_alive_task.sh
  nohup ./keep_alive_task.sh > keep_alive_status.log 2>&1 &
  echo -e "${GREEN}保活已启动（后台运行）。停止：pkill -f keep_alive_task.sh${NC}"
}

# ====== 参数解析 ======
ACTION="deploy"
ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--view) ACTION="view"; shift ;;
    --set-ip) ACTION="setip"; ARG="$2"; shift 2 ;;
    --deploy) ACTION="deploy"; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) echo -e "${RED}未知参数: $1${NC}"; show_help; exit 1 ;;
  esac
done

# ====== 动作分发 ======
case "$ACTION" in
  view)
    if [[ -f "$NODE_INFO_FILE" ]]; then
      echo -e "${GREEN}========================================${NC}"
      echo -e "${GREEN}           节点信息查看                ${NC}"
      echo -e "${GREEN}========================================${NC}"
      cat "$NODE_INFO_FILE"
    else
      echo -e "${RED}未找到节点信息文件：$NODE_INFO_FILE${NC}"
      echo -e "${YELLOW}请先部署生成节点信息（bash test.sh）${NC}"
    fi
    ;;

  setip)
    if [[ -z "$ARG" ]]; then
      echo -e "${RED}用法错误：--set-ip <IP|auto>${NC}"
      exit 1
    fi
    # 如果 CFIP 环境变量已设置，优先尊重环境变量，不强制覆盖
    if [[ -n "$CFIP" && "$ARG" != "auto" ]]; then
      echo -e "${YELLOW}检测到已设置环境变量 CFIP=$CFIP，如需覆盖请先清空该变量或改为 auto${NC}"
    fi
    if [[ "$ARG" == "auto" ]]; then
      auto_select_ip || exit 1
    else
      set_cfip_in_app "$ARG" || exit 1
      echo "Preferred_IP=$ARG" >> "$NODE_INFO_FILE"
    fi
    ;;

  deploy)
    echo -e "${GREEN}开始部署...${NC}"
    maybe_start_keepalive
    # 这里按你的项目实际需要启动应用。常见两种：
    # A) 本脚本作为 Start command：最终执行 python app.py
    python3 "$APP_FILE"
    # B) 若你在别处拉起服务，这里可以换成其他命令
    ;;

  *)
    show_help; exit 1 ;;
esac
