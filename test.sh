#!/usr/bin/env bash

# ====== 基本配置（运行前 export）======
# export HF_TOKEN="你的 HuggingFace Token（低权限即可）"
# export SERVICE_PORT="服务端口"
# export SUB_PATH_VALUE="订阅路径"
# export NODE_INFO_FILE="节点信息保存文件路径"
# export DECODED_NODES="节点信息内容"
# export NODE_INFO="订阅链接信息"
# export KEEP_ALIVE_HF="true/false"
# export SPACE_ID="你的 Hugging Face Space ID"

# ====== 获取公网 IP ======
if command -v curl &> /dev/null; then
    PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "获取失败")
    if [ "$PUBLIC_IP" != "获取失败" ]; then
        SAVE_INFO="${SAVE_INFO}
订阅地址: http://$PUBLIC_IP:$SERVICE_PORT/$SUB_PATH_VALUE
管理面板: http://$PUBLIC_IP:$SERVICE_PORT"
    fi
fi

# ====== 本地信息 ======
SAVE_INFO="${SAVE_INFO}
本地订阅: http://localhost:$SERVICE_PORT/$SUB_PATH_VALUE
本地面板: http://localhost:$SERVICE_PORT

=== 节点信息 ===
$DECODED_NODES

=== 订阅链接 ===
$NODE_INFO

=== 管理命令 ===
查看日志: tail -f \$(pwd)/app.log
停止主服务: kill \$APP_PID
重启主服务: kill \$APP_PID && nohup python3 app.py > app.log 2>&1 &
查看进程: ps aux | grep app.py"

# ====== 保活服务 ======
if [ "$KEEP_ALIVE_HF" = "true" ]; then
    SAVE_INFO="${SAVE_INFO}
停止保活服务: pkill -f keep_alive_task.sh && rm -f keep_alive_task.sh keep_alive_status.log"

    cat > keep_alive_task.sh <<'EOF'
#!/usr/bin/env bash
while true; do
    curl -s -H "Authorization: Bearer $HF_TOKEN" \
         -X POST "https://huggingface.co/api/spaces/${SPACE_ID}/runtime/ping" \
         -o /dev/null
    sleep 120
done
EOF
    chmod 700 keep_alive_task.sh
    nohup ./keep_alive_task.sh > keep_alive_status.log 2>&1 &
fi

# ====== 分流说明 ======
SAVE_INFO="${SAVE_INFO}

=== 分流说明 ===
- 已集成 YouTube 分流优化到 xray 配置
- 分流出口节点为你自己配置的 my_youtube_node（可替换为解锁节点）
- 无需额外配置，透明分流"

# ====== 保存节点信息 ======
echo "$SAVE_INFO" > "$NODE_INFO_FILE"
echo -e "\033[32m节点信息已保存到 $NODE_INFO_FILE\033[0m"
echo -e "\033[33m使用脚本选项3或运行带 -v 参数可随时查看节点信息\033[0m"

# ====== 部署完成提示 ======
echo -e "\033[33m=== 重要提示 ===\033[0m"
echo -e "\033[32m部署已完成，节点信息已成功生成\033[0m"
echo -e "\033[32m可以立即使用订阅地址添加到客户端\033[0m"
echo -e "\033[32mYouTube 分流已集成到 xray 配置，无需额外设置\033[0m"
echo -e "\033[32m服务将持续在后台运行\033[0m"
echo
echo -e "\033[32m部署完成！感谢使用！\033[0m"

exit 0
