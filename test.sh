#!/bin/bash
# =========================================
# 优化版一键部署脚本（融合版）
# Author: gmddd002
# 仓库: https://github.com/gmddd002/free-vps-py
# 项目: https://github.com/gmddd002/python-xray-argo
# 融合来源: https://github.com/byJoey/free-vps-py (test (2).sh)
# =========================================
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # 无颜色

LOGFILE="/root/python-xray-argo/app.log"
NODE_INFO_FILE="$HOME/.xray_nodes_info"
PROJECT_DIR_NAME="python-xray-argo"

# UUID 生成函数
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 &> /dev/null; then
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    else
        hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/' | tr '[:upper:]' '[:lower:]'
    fi
}

# Hugging Face 保活配置函数
configure_hf_keep_alive() {
    echo -e "${YELLOW}是否设置 Hugging Face API 自动保活? (y/n)${NC}" | tee -a "$LOGFILE"
    read -p "> " SETUP_KEEP_ALIVE
    if [ "$SETUP_KEEP_ALIVE" = "y" ] || [ "$SETUP_KEEP_ALIVE" = "Y" ]; then
        echo -e "${YELLOW}请输入 Hugging Face Token:${NC}" | tee -a "$LOGFILE"
        read -sp "Token: " HF_TOKEN
        echo
        if [ -z "$HF_TOKEN" ]; then
            echo -e "${RED}错误：Token 不能为空。保活设置取消。${NC}" | tee -a "$LOGFILE"
            return
        fi
        echo -e "${YELLOW}请输入仓库ID (e.g., joeyhuangt/aaaa):${NC}" | tee -a "$LOGFILE"
        read -p "Repo ID: " HF_REPO_ID
        if [ -z "$HF_REPO_ID" ]; then
            echo -e "${RED}错误：仓库ID 不能为空。保活设置取消。${NC}" | tee -a "$LOGFILE"
            return
        fi
        KEEP_ALIVE_HF="true"
        echo -e "${GREEN}Hugging Face 保活已设置！目标仓库: $HF_REPO_ID${NC}" | tee -a "$LOGFILE"
    fi
}

# 主脚本开始
echo -e "${GREEN}========================================${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN} 优化版 Python Xray Argo 一键部署脚本 ${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}========================================${NC}" | tee -a "$LOGFILE"

# 模式选择
echo -e "${YELLOW}请选择模式 (默认1 - 一键自动化):${NC}" | tee -a "$LOGFILE"
echo -e "${BLUE}1) 一键模式 - 自动配置并启动${NC}"
echo -e "${BLUE}2) 自定义模式 - 详细配置选项${NC}"
echo -e "${BLUE}3) 查看节点信息${NC}"
echo -e "${BLUE}4) 查看 Hugging Face 保活状态${NC}"
read -p "请输入选择 (1/2/3/4): " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-1}  # 默认1

# 模式 3：查看节点信息
if [ "$MODE_CHOICE" = "3" ]; then
    if [ -f "$NODE_INFO_FILE" ]; then
        echo -e "${GREEN}========================================${NC}" | tee -a "$LOGFILE"
        echo -e "${GREEN}          节点信息查看          ${NC}" | tee -a "$LOGFILE"
        echo -e "${GREEN}========================================${NC}" | tee -a "$LOGFILE"
        cat "$NODE_INFO_FILE" | tee -a "$LOGFILE"
    else
        echo -e "${RED}未找到节点信息文件，请先部署！${NC}" | tee -a "$LOGFILE"
    fi
    exit 0
fi

# 模式 4：查看保活状态
if [ "$MODE_CHOICE" = "4" ]; then
    echo -e "${GREEN}>>> 检查 Hugging Face API 保活状态...${NC}" | tee -a "$LOGFILE"
    cd "/root/$PROJECT_DIR_NAME" || {
        echo -e "${RED}项目目录不存在，请先部署！${NC}" | tee -a "$LOGFILE"
        exit 1
    }
    KEEPALIVE_PID=$(pgrep -f "keep_alive_task.sh")
    if [ -n "$KEEPALIVE_PID" ]; then
        echo -e "服务状态: ${GREEN}运行中${NC}" | tee -a "$LOGFILE"
        echo -e "进程PID: ${BLUE}$KEEPALIVE_PID${NC}" | tee -a "$LOGFILE"
        if [ -f "keep_alive_status.log" ]; then
            echo -e "${YELLOW}最近保活状态:${NC}" | tee -a "$LOGFILE"
            cat keep_alive_status.log | tee -a "$LOGFILE"
        else
            echo -e "${YELLOW}尚未生成状态日志，请稍等（最多2分钟）。${NC}" | tee -a "$LOGFILE"
        fi
    else
        echo -e "服务状态: ${RED}未运行${NC}" | tee -a "$LOGFILE"
        echo -e "${YELLOW}提示: 未设置保活或任务未启动。${NC}" | tee -a "$LOGFILE"
    fi
    exit 0
fi

# 检查并安装依赖
echo -e "${GREEN}>>> 安装必要依赖...${NC}" | tee -a "$LOGFILE"
apt-get update
if ! command -v python3 &> /dev/null; then
    apt-get install -y python3 python3-pip
fi
if ! command -v screen &> /dev/null; then
    apt-get install -y screen
fi
if ! command -v jq &> /dev/null; then
    apt-get install -y jq
fi
if ! command -v curl &> /dev/null; then
    apt-get install -y curl
fi
if ! command -v git &> /dev/null; then
    apt-get install -y git
fi

echo -e "${GREEN}>>> 安装 cloudflared...${NC}" | tee -a "$LOGFILE"
if ! command -v cloudflared &> /dev/null; then
    curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i cloudflared.deb 2>/dev/null || apt-get install -f -y
    rm -f cloudflared.deb
else
    echo -e "${YELLOW}cloudflared 已安装，跳过。${NC}" | tee -a "$LOGFILE"
fi

# 克隆项目
echo -e "${GREEN}>>> 克隆仓库并安装依赖...${NC}" | tee -a "$LOGFILE"
cd /root
rm -rf "$PROJECT_DIR_NAME"
if ! git clone https://github.com/gmddd002/python-xray-argo.git "$PROJECT_DIR_NAME"; then
    echo -e "${RED}克隆仓库失败，请检查网络！${NC}" | tee -a "$LOGFILE"
    exit 1
fi
cd "$PROJECT_DIR_NAME"
if [ -f "requirements.txt" ]; then
    pip3 install -r requirements.txt
else
    echo -e "${RED}未找到 requirements.txt 文件！${NC}" | tee -a "$LOGFILE"
    exit 1
fi

# 检查 app.py 存在
if [ ! -f "app.py" ]; then
    echo -e "${RED}未找到 app.py 文件！${NC}" | tee -a "$LOGFILE"
    exit 1
fi

# 配置 app.py
UUID=$(generate_uuid)
echo -e "${GREEN}自动生成 UUID: $UUID${NC}" | tee -a "$LOGFILE"
sed -i "s/UUID = os.environ.get('UUID', '[^']*')/UUID = os.environ.get('UUID', '$UUID')/" app.py

if [ "$MODE_CHOICE" = "2" ]; then
    # 自定义模式
    echo -e "${YELLOW}当前节点名称: $(grep "NAME = " app.py | head -1 | cut -d"'" -f4)${NC}" | tee -a "$LOGFILE"
    read -p "请输入节点名称 (留空保持不变): " NAME_INPUT
    if [ -n "$NAME_INPUT" ]; then
        sed -i "s/NAME = os.environ.get('NAME', '[^']*')/NAME = os.environ.get('NAME', '$NAME_INPUT')/" app.py
        echo -e "${GREEN}节点名称已设置为: $NAME_INPUT${NC}" | tee -a "$LOGFILE"
    fi
    echo -e "${YELLOW}当前优选IP: $(grep "CFIP = " app.py | cut -d"'" -f4)${NC}" | tee -a "$LOGFILE"
    read -p "请输入优选IP/域名 (留空使用默认 joeyblog.net): " CFIP_INPUT
    CFIP_INPUT=${CFIP_INPUT:-joeyblog.net}
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', '$CFIP_INPUT')/" app.py
    echo -e "${GREEN}优选IP已设置为: $CFIP_INPUT${NC}" | tee -a "$LOGFILE"
    configure_hf_keep_alive
else
    # 一键模式默认配置
    sed -i "s/CFIP = os.environ.get('CFIP', '[^']*')/CFIP = os.environ.get('CFIP', 'joeyblog.net')/" app.py
    echo -e "${GREEN}优选IP已设置为: joeyblog.net${NC}" | tee -a "$LOGFILE"
fi

# 自动端口分配
echo -e "${GREEN}>>> 分配未占用的端口...${NC}" | tee -a "$LOGFILE"
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
sed -i "s/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or [0-9]*)/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $PORT)/" app.py
echo -e "${BLUE}分配端口: $PORT${NC}" | tee -a "$LOGFILE"

# 添加 YouTube 分流和 80 端口节点
echo -e "${GREEN}>>> 添加 YouTube 分流优化...${NC}" | tee -a "$LOGFILE"
python3 - << 'EOF' > /dev/null
# coding: utf-8
import os, base64, json, subprocess, time

with open('app.py', 'r', encoding='utf-8') as f:
    content = f.read()

old_config = 'config ={"log":{"access":"/dev/null","error":"/dev/null","loglevel":"none",},"inbounds":[{"port":ARGO_PORT ,"protocol":"vless","settings":{"clients":[{"id":UUID ,"flow":"xtls-rprx-vision",},],"decryption":"none","fallbacks":[{"dest":3001 },{"path":"/vless-argo","dest":3002 },{"path":"/vmess-argo","dest":3003 },{"path":"/trojan-argo","dest":3004 },],},"streamSettings":{"network":"tcp",},},{"port":3001 ,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[{"id":UUID },],"decryption":"none"},"streamSettings":{"network":"ws","security":"none"}},{"port":3002 ,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[{"id":UUID ,"level":0 }],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-argo"}},"sniffing":{"enabled":True ,"destOverride":["http","tls","quic"],"metadataOnly":False }},{"port":3003 ,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[{"id":UUID ,"alterId":0 }]},"streamSettings":{"network":"ws","wsSettings":{"path":"/vmess-argo"}},"sniffing":{"enabled":True ,"destOverride":["http","tls","quic"],"metadataOnly":False }},{"port":3004 ,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[{"password":UUID },]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/trojan-argo"}},"sniffing":{"enabled":True ,"destOverride":["http","tls","quic"],"metadataOnly":False }},],"outbounds":[{"protocol":"freedom","tag": "direct" },{"protocol":"blackhole","tag":"block"}]}'

new_config = '''config = {
    "log": {"access": "/dev/null", "error": "/dev/null", "loglevel": "none"},
    "inbounds": [
        {"port": ARGO_PORT, "protocol": "vless", "settings": {"clients": [{"id": UUID, "flow": "xtls-rprx-vision"}], "decryption": "none", "fallbacks": [{"dest": 3001}, {"path": "/vless-argo", "dest": 3002}, {"path": "/vmess-argo", "dest": 3003}, {"path": "/trojan-argo", "dest": 3004}]}, "streamSettings": {"network": "tcp"}},
        {"port": 3001, "listen": "127.0.0.1", "protocol": "vless", "settings": {"clients": [{"id": UUID}], "decryption": "none"}, "streamSettings": {"network": "ws", "security": "none"}},
        {"port": 3002, "listen": "127.0.0.1", "protocol": "vless", "settings": {"clients": [{"id": UUID, "level": 0}], "decryption": "none"}, "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "/vless-argo"}}, "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False}},
        {"port": 3003, "listen": "127.0.0.1", "protocol": "vmess", "settings": {"clients": [{"id": UUID, "alterId": 0}]}, "streamSettings": {"network": "ws", "wsSettings": {"path": "/vmess-argo"}}, "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False}},
        {"port": 3004, "listen": "127.0.0.1", "protocol": "trojan", "settings": {"clients": [{"password": UUID}]}, "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "/trojan-argo"}}, "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False}}
    ],
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "vmess", "tag": "youtube", "settings": {"vnext": [{"address": "172.233.171.224", "port": 16416, "users": [{"id": "8c1b9bea-cb51-43bb-a65c-0af31bbbf145", "alterId": 0}]}]}, "streamSettings": {"network": "tcp"}},
        {"protocol": "blackhole", "tag": "block"}
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [{"type": "field", "domain": ["youtube.com", "youtu.be", "instagram.com", "discord.com", "facebook.com", "fikfap.com", "telegram.org", "t.me", "googlevideo.com", "ytimg.com", "gstatic.com", "googleapis.com", "ggpht.com", "googleusercontent.com"], "outboundTag": "youtube"}]
    }
}'''

content = content.replace(old_config, new_config)

old_generate_function = '''# Generate links and subscription content
async def generate_links(argo_domain):
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"')
    ISP = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()

    time.sleep(2)
    VMESS = {"v": "2", "ps": f"{NAME}-{ISP}", "add": CFIP, "port": CFPORT, "id": UUID, "aid": "0", "scy": "none", "net": "ws", "type": "none", "host": argo_domain, "path": "/vmess-argo?ed=2560", "tls": "tls", "sni": argo_domain, "alpn": "", "fp": "chrome"}
 
    list_txt = f"""
vless://{UUID}@{CFIP}:{CFPORT}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}
  
vmess://{ base64.b64encode(json.dumps(VMESS).encode('utf-8')).decode('utf-8')}

trojan://{UUID}@{CFIP}:{CFPORT}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}
    """
    
    with open(os.path.join(FILE_PATH, 'list.txt'), 'w', encoding='utf-8') as list_file:
        list_file.write(list_txt)

    sub_txt = base64.b64encode(list_txt.encode('utf-8')).decode('utf-8')
    with open(os.path.join(FILE_PATH, 'sub.txt'), 'w', encoding='utf-8') as sub_file:
        sub_file.write(sub_txt)
        
    print(sub_txt)
    
    print(f"{FILE_PATH}/sub.txt saved successfully")
    
    # Additional actions
    send_telegram()
    upload_nodes()
 
    return sub_txt'''

new_generate_function = '''# Generate links and subscription content
async def generate_links(argo_domain):
    meta_info = subprocess.run(['curl', '-s', 'https://speed.cloudflare.com/meta'], capture_output=True, text=True)
    meta_info = meta_info.stdout.split('"')
    ISP = f"{meta_info[25]}-{meta_info[17]}".replace(' ', '_').strip()

    time.sleep(2)
    
    # TLS节点
    VMESS_TLS = {"v": "2", "ps": f"{NAME}-{ISP}-TLS", "add": CFIP, "port": CFPORT, "id": UUID, "aid": "0", "scy": "none", "net": "ws", "type": "none", "host": argo_domain, "path": "/vmess-argo?ed=2560", "tls": "tls", "sni": argo_domain, "alpn": "", "fp": "chrome"}
    
    # 无TLS节点 (80端口)
    VMESS_80 = {"v": "2", "ps": f"{NAME}-{ISP}-80", "add": CFIP, "port": "80", "id": UUID, "aid": "0", "scy": "none", "net": "ws", "type": "none", "host": argo_domain, "path": "/vmess-argo?ed=2560", "tls": "", "sni": "", "alpn": "", "fp": ""}
 
    list_txt = f"""
vless://{UUID}@{CFIP}:{CFPORT}?encryption=none&security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}-TLS
  
vmess://{ base64.b64encode(json.dumps(VMESS_TLS).encode('utf-8')).decode('utf-8')}

trojan://{UUID}@{CFIP}:{CFPORT}?security=tls&sni={argo_domain}&fp=chrome&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}-TLS

vless://{UUID}@{CFIP}:80?encryption=none&security=none&type=ws&host={argo_domain}&path=%2Fvless-argo%3Fed%3D2560#{NAME}-{ISP}-80

vmess://{ base64.b64encode(json.dumps(VMESS_80).encode('utf-8')).decode('utf-8')}

trojan://{UUID}@{CFIP}:80?security=none&type=ws&host={argo_domain}&path=%2Ftrojan-argo%3Fed%3D2560#{NAME}-{ISP}-80
    """
    
    with open(os.path.join(FILE_PATH, 'list.txt'), 'w', encoding='utf-8') as list_file:
        list_file.write(list_txt)

    sub_txt = base64.b64encode(list_txt.encode('utf-8')).decode('utf-8')
    with open(os.path.join(FILE_PATH, 'sub.txt'), 'w', encoding='utf-8') as sub_file:
        sub_file.write(sub_txt)
        
    print(sub_txt)
    
    print(f"{FILE_PATH}/sub.txt saved successfully")
    
    # Additional actions
    send_telegram()
    upload_nodes()
 
    return sub_txt'''

content = content.replace(old_generate_function, new_generate_function)

with open('app.py', 'w', encoding='utf-8') as f:
    f.write(content)
EOF

# 启动服务
echo -e "${GREEN}>>> 启动服务...${NC}" | tee -a "$LOGFILE"
pkill -f "python3 app.py" > /dev/null 2>&1
nohup python3 app.py 2>&1 | tee -a "$LOGFILE" &
APP_PID=$!
sleep 2
if ! ps -p "$APP_PID" > /dev/null 2>&1; then
    echo -e "${RED}服务启动失败，请检查日志: tail -f $LOGFILE${NC}" | tee -a "$LOGFILE"
    exit 1
fi
echo -e "${GREEN}服务已启动，PID: $APP_PID${NC}" | tee -a "$LOGFILE"

# 保活任务
if [ "$KEEP_ALIVE_HF" = "true" ]; then
    echo -e "${GREEN}>>> 创建并启动 Hugging Face API 保活任务...${NC}" | tee -a "$LOGFILE"
    echo "#!/bin/bash" > keep_alive_task.sh
    echo "while true; do" >> keep_alive_task.sh
    echo "    status_code=\$(curl -s -o /dev/null -w \"%{http_code}\" --header \"Authorization: Bearer $HF_TOKEN\" \"https://huggingface.co/api/spaces/$HF_REPO_ID\")" >> keep_alive_task.sh
    echo "    if [ \"\$status_code\" -eq 200 ]; then" >> keep_alive_task.sh
    echo "        echo \"保活成功 (Space: $HF_REPO_ID, 状态码: 200) - \$(date '+%Y-%m-%d %H:%M:%S')\" > keep_alive_status.log" >> keep_alive_task.sh
    echo "    else" >> keep_alive_task.sh
    echo "        echo \"保活失败 (Space: $HF_REPO_ID, 状态码: \$status_code) - \$(date '+%Y-%m-%d %H:%M:%S')\" > keep_alive_status.log" >> keep_alive_task.sh
    echo "    fi" >> keep_alive_task.sh
    echo "    sleep 120" >> keep_alive_task.sh
    echo "done" >> keep_alive_task.sh
    chmod +x keep_alive_task.sh
    nohup ./keep_alive_task.sh >/dev/null 2>&1 &
    KEEPALIVE_PID=$!
    echo -e "${GREEN}Hugging Face 保活任务启动（PID: $KEEPALIVE_PID）。${NC}" | tee -a "$LOGFILE"
fi

# 等待节点生成
echo -e "${YELLOW}等待节点信息生成（最多5分钟）...${NC}" | tee -a "$LOGFILE"
MAX_WAIT=300
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if [ -f "sub.txt" ] && [ -f "boot.log" ]; then
        SUB_B64=$(cat sub.txt)
        if [ -n "$SUB_B64" ]; then
            break
        fi
    fi
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 5))
done
if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo -e "${RED}等待超时，请检查日志: tail -f $LOGFILE${NC}" | tee -a "$LOGFILE"
    exit 1
fi

# 提取信息
ARGO_ADDR=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' boot.log | head -n1)
ARGO_ADDR=${ARGO_ADDR#https://}
DECODED_LINKS=$(echo "$SUB_B64" | base64 -d)
VLESS_URI=$(echo "$DECODED_LINKS" | grep -oE 'vless://[^#]+#[^ ]+')
VMESS_URI=$(echo "$DECODED_LINKS" | grep -oE 'vmess://[^ ]+')
TROJAN_URI=$(echo "$DECODED_LINKS" | grep -oE 'trojan://[^#]+#[^ ]+')
UUID=$(echo "$VLESS_URI" | grep -oP '(?<=://)[^@]+')
PORT_NUM=$(echo "$VLESS_URI" | awk -F'[@:]' '{print $3}' | cut -d'?' -f1)
SNI=$(echo "$VLESS_URI" | grep -oP '(?<=&sni=)[^&]+')
HOST=$(echo "$VLESS_URI" | grep -oP '(?<=&host=)[^&]+')
NET_TYPE=$(echo "$VLESS_URI" | grep -oP '(?<=&type=)[^&]+')

# 输出节点信息
echo -e "${GREEN}========================================${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}          部署完成！          ${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}========================================${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}临时隧道: $ARGO_ADDR${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}Base64 订阅: $SUB_B64${NC}" | tee -a "$LOGFILE"
echo -e "${GREEN}节点连接:${NC}" | tee -a "$LOGFILE"
echo "  VLESS: $VLESS_URI" | tee -a "$LOGFILE"
echo "  VMESS: $VMESS_URI" | tee -a "$LOGFILE"
echo "  Trojan: $TROJAN_URI" | tee -a "$LOGFILE"
echo -e "${GREEN}参数:${NC}" | tee -a "$LOGFILE"
echo "  UUID: $UUID" | tee -a "$LOGFILE"
echo "  端口: $PORT_NUM" | tee -a "$LOGFILE"
echo "  SNI: $SNI" | tee -a "$LOGFILE"
echo "  Host: $HOST" | tee -a "$LOGFILE"
echo "  传输: $NET_TYPE" | tee -a "$LOGFILE"

# 保存节点信息
SAVE_INFO="========================================
          节点信息保存
========================================
部署时间: $(date)
UUID: $UUID
端口: $PORT
隧道: $ARGO_ADDR
订阅: $SUB_B64
VLESS: $VLESS_URI
VMESS: $VMESS_URI
Trojan: $TROJAN_URI
=== 管理命令 ===
查看日志: tail -f $LOGFILE
停止服务: kill $APP_PID
重启服务: kill $APP_PID && nohup python3 app.py > $LOGFILE 2>&1 &
查看进程: ps aux | grep app.py"
if [ "$KEEP_ALIVE_HF" = "true" ]; then
    SAVE_INFO="$SAVE_INFO
停止保活: kill $KEEPALIVE_PID && rm keep_alive_task.sh keep_alive_status.log"
fi
echo "$SAVE_INFO" > "$NODE_INFO_FILE"
echo -e "${GREEN}节点信息保存到 $NODE_INFO_FILE${NC}" | tee -a "$LOGFILE"

# 部署完成提示
echo -e "${GREEN}>>> 部署完成！${NC}" | tee -a "$LOGFILE"
echo -e "${YELLOW}管理命令:${NC}" | tee -a "$LOGFILE"
echo -e "  查看日志: tail -f $LOGFILE" | tee -a "$LOGFILE"
echo -e "  停止服务: kill $APP_PID" | tee -a "$LOGFILE"
echo -e "  重启服务: kill $APP_PID && nohup python3 app.py > $LOGFILE 2>&1 &" | tee -a "$LOGFILE"
echo -e "  查看节点信息: bash $0 3" | tee -a "$LOGFILE"
echo -e "  查看保活状态: bash $0 4" | tee -a "$LOGFILE"
if [ "$KEEP_ALIVE_HF" = "true" ]; then
    echo -e "  停止保活: kill $KEEPALIVE_PID && rm keep_alive_task.sh keep_alive_status.log" | tee -a "$LOGFILE"
fi

exit 0
