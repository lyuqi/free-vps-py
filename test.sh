#!/bin/bash
# =========================================
# 自控版一键部署脚本
# Author: gmddd002
# 仓库: https://github.com/gmddd002/free-vps-py
# 项目: https://github.com/gmddd002/python-xray-argo
# =========================================

NODE_INFO_FILE="$HOME/.my_nodes_info"
PROJECT_DIR_NAME="python-xray-argo"

echo "======================================="
echo "   私有自控版 Xray Argo 一键部署脚本"
echo "   所有数据与代码均来自 gmddd002 仓库"
echo "======================================="

# Step 1: 检查环境
echo "[*] 检查环境..."
if ! command -v python3 &> /dev/null; then
    echo "未找到 Python3，正在安装..."
    sudo apt-get update && sudo apt-get install -y python3 python3-pip
fi

if ! python3 -c "import requests" &> /dev/null; then
    echo "安装 Python 依赖 requests..."
    pip3 install requests
fi

# Step 2: 下载项目代码（仅从你自己的仓库获取）
if [ ! -d "$PROJECT_DIR_NAME" ]; then
    echo "[*] 克隆你的项目仓库..."
    git clone https://github.com/gmddd002/python-xray-argo.git "$PROJECT_DIR_NAME"
fi

cd "$PROJECT_DIR_NAME" || exit 1

# Step 3: 用户输入参数
read -p "请输入 UUID (留空自动生成): " UUID_INPUT
if [ -z "$UUID_INPUT" ]; then
    UUID_INPUT=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
    echo "自动生成 UUID: $UUID_INPUT"
fi

read -p "请输入节点名称 (自定义标识): " NAME_INPUT

# Step 4: Hugging Face 保活设置
echo "配置 Hugging Face 保活..."
read -p "请输入 Hugging Face Token: " HF_TOKEN
read -p "请输入 Hugging Face Repo ID (例如: gmddd002/myspace): " HF_REPO_ID

# Step 5: 修改 app.py 配置
if [ ! -f "app.py" ]; then
    echo "未找到 app.py，请确认仓库内容正确。"
    exit 1
fi

sed -i "s/UUID = os.environ.get('UUID'.*/UUID = os.environ.get('UUID', '$UUID_INPUT')/" app.py
sed -i "s/NAME = os.environ.get('NAME'.*/NAME = os.environ.get('NAME', '$NAME_INPUT')/" app.py

# Step 6: 启动服务
echo "[*] 启动服务..."
nohup python3 app.py > app.log 2>&1 &
APP_PID=$!

# Step 7: 保活任务（完全闭环，只写本地日志）
cat > keep_alive_task.sh <<EOF
#!/bin/bash
while true; do
    status_code=\$(curl -s -o /dev/null -w "%{http_code}" --header "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api/spaces/$HF_REPO_ID")
    if [ "\$status_code" -eq 200 ]; then
        echo "\$(date): Hugging Face Space 保活成功 (状态码: 200)" > keep_alive_status.log
    else
        echo "\$(date): Hugging Face Space 保活失败 (状态码: \$status_code)" > keep_alive_status.log
    fi
    sleep 120
done
EOF
chmod +x keep_alive_task.sh
nohup ./keep_alive_task.sh >/dev/null 2>&1 &
KEEPALIVE_PID=$!

# Step 8: 保存节点信息（本地文件，仅自己可见）
cat > "$NODE_INFO_FILE" <<EOF
=======================================
           节点信息保存
=======================================
部署时间: $(date)
UUID: $UUID_INPUT
节点名称: $NAME_INPUT
服务PID: $APP_PID
保活PID: $KEEPALIVE_PID
HuggingFace Repo: $HF_REPO_ID

=== 管理命令 ===
查看日志: tail -f app.log
停止服务: kill $APP_PID
停止保活: kill $KEEPALIVE_PID
=======================================
EOF

echo "======================================="
echo " 部署完成！信息已保存到 $NODE_INFO_FILE"
echo " 查看日志: tail -f app.log"
echo "======================================="
