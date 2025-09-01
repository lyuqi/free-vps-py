#!/bin/bash

# ====== 颜色定义 ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NODE_INFO_FILE="$HOME/.xray_nodes_info"
APP_FILE="app.py"

# ====== Cloudflare 官方 IPv4 段（可扩展） ======
IP_LIST=(
    104.16.0.1
    104.17.0.1
    104.18.0.1
    104.19.0.1
    104.20.0.1
    172.64.0.1
    172.65.0.1
    172.66.0.1
    172.67.0.1
)

# ====== 帮助信息 ======
show_help() {
    echo -e "${YELLOW}用法:${NC} bash test.sh [选项]"
    echo "  -v, --view         查看节点信息"
    echo "  --set-ip <IP>      手动设置优选 IP"
    echo "  --set-ip auto      自动测速并设置优选 IP"
    echo "  -h, --help         显示帮助信息"
}

# ====== 自动测速优选 IP ======
auto_select_ip() {
    echo -e "${BLUE}开始自动测速优选 IP...${NC}"
    BEST_IP=""
    BEST_PING=9999

    for ip in "${IP_LIST[@]}"; do
        ping_time=$(ping -c 1 -W 1 $ip 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
        if [[ -n "$ping_time" ]]; then
            echo -e "测试 $ip 延迟: ${ping_time} ms"
            if (( $(echo "$ping_time < $BEST_PING" | bc -l) )); then
                BEST_PING=$ping_time
                BEST_IP=$ip
            fi
        fi
    done

    if [[ -n "$BEST_IP" ]]; then
        echo -e "${GREEN}优选 IP: $BEST_IP (延迟 ${BEST_PING}ms)${NC}"
        if [[ -f "$APP_FILE" ]]; then
            sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '$BEST_IP')/" "$APP_FILE"
            echo -e "${GREEN}已将 app.py 中的默认 CFIP 设置为: $BEST_IP${NC}"
        else
            echo -e "${RED}未找到 $APP_FILE 文件，无法替换${NC}"
        fi
        echo "Preferred_IP=$BEST_IP" >> "$NODE_INFO_FILE"
    else
        echo -e "${RED}未找到可用 IP${NC}"
    fi
}

# ====== 参数解析 ======
ACTION="deploy"
PREFERRED_IP=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--view) ACTION="view"; shift ;;
        --set-ip) ACTION="setip"; PREFERRED_IP="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo -e "${RED}未知参数: $1${NC}"; show_help; exit 1 ;;
    esac
done

# ====== 功能实现 ======
if [ "$ACTION" = "view" ]; then
    if [ -f "$NODE_INFO_FILE" ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}           节点信息查看           ${NC}"
        echo -e "${GREEN}========================================${NC}"
        cat "$NODE_INFO_FILE"
    else
        echo -e "${RED}未找到节点信息文件${NC}"
        echo -e "${YELLOW}请先运行部署脚本生成节点信息${NC}"
    fi

elif [ "$ACTION" = "setip" ]; then
    if [ "$PREFERRED_IP" = "auto" ]; then
        auto_select_ip
    elif [ -n "$PREFERRED_IP" ]; then
        echo -e "${BLUE}正在设置优选 IP 为: $PREFERRED_IP${NC}"
        if [[ -f "$APP_FILE" ]]; then
            sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '$PREFERRED_IP')/" "$APP_FILE"
            echo -e "${GREEN}已将 app.py 中的默认 CFIP 设置为: $PREFERRED_IP${NC}"
        else
            echo -e "${RED}未找到 $APP_FILE 文件，无法替换${NC}"
        fi
        echo "Preferred_IP=$PREFERRED_IP" >> "$NODE_INFO_FILE"
    else
        echo -e "${RED}错误:${NC} 你必须提供一个 IP 或使用 auto，例如：--set-ip auto"
        exit 1
    fi

else
    echo -e "${GREEN}开始部署...${NC}"
    python3 "$APP_FILE"
fi
