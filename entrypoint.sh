#!/bin/sh
# msd_lite 容器入口脚本
#
# 用法一（推荐）：用环境变量控制，脚本自动渲染 XML 配置
#   docker run -d --network host -e MSD_PORT=7088 -e MSD_IFACE=eth0 msd_lite:latest
#
# 用法二：挂载自己的配置文件
#   docker run -d --network host -v /my/msd_lite.conf:/etc/msd_lite/msd_lite.conf:ro \
#     msd_lite:latest -c /etc/msd_lite/msd_lite.conf
#
# 用法三：直接透传 msd_lite 原生参数
#   docker run -d --network host msd_lite:latest -c /path/conf -v
set -e

BIN="/usr/local/bin/msd_lite"
TPL="/etc/msd_lite/msd_lite.conf.template"
CONF="/etc/msd_lite/msd_lite.conf"
log() { echo "[msd_lite] $*"; }

# 参数以 - 开头 => 直接透传给 msd_lite
case "$1" in
  -*)
    log "透传原始参数: $*"
    exec "$BIN" "$@"
    ;;
esac

# ---- 若配置文件已存在（用户挂载），则直接使用 ----
if [ -f "$CONF" ] && [ ! -f "${CONF}.generated" ]; then
    log "使用已有配置文件: $CONF"
else
    log "根据环境变量生成配置..."
    # 从环境变量取值，带默认值
    : "${MSD_PORT:=7088}"
    : "${MSD_IFACE:=eth0}"
    : "${MSD_LOG_LEVEL:=6}"
    : "${MSD_PRECACHE:=4096}"
    : "${MSD_RINGBUF:=1024}"
    : "${MSD_THREADS:=1}"
    : "${MSD_SNDBUF:=512}"
    : "${MSD_SNDLOWAT:=64}"
    : "${MSD_RCVBUF:=512}"
    : "${MSD_RCVLOWAT:=48}"
    : "${MSD_RCVTIMEOUT:=2}"

    sed -e "s|__MSD_PORT__|${MSD_PORT}|g" \
        -e "s|__MSD_IFACE__|${MSD_IFACE}|g" \
        -e "s|__MSD_LOG_LEVEL__|${MSD_LOG_LEVEL}|g" \
        -e "s|__MSD_PRECACHE__|${MSD_PRECACHE}|g" \
        -e "s|__MSD_RINGBUF__|${MSD_RINGBUF}|g" \
        -e "s|__MSD_THREADS__|${MSD_THREADS}|g" \
        -e "s|__MSD_SNDBUF__|${MSD_SNDBUF}|g" \
        -e "s|__MSD_SNDLOWAT__|${MSD_SNDLOWAT}|g" \
        -e "s|__MSD_RCVBUF__|${MSD_RCVBUF}|g" \
        -e "s|__MSD_RCVLOWAT__|${MSD_RCVLOWAT}|g" \
        -e "s|__MSD_RCVTIMEOUT__|${MSD_RCVTIMEOUT}|g" \
        "$TPL" > "$CONF"
    touch "${CONF}.generated"

    log "监听端口   : ${MSD_PORT}"
    log "组播网卡   : ${MSD_IFACE}"
    log "线程数     : ${MSD_THREADS}"
    log "预缓存     : ${MSD_PRECACHE} KB"
    log "环形缓冲   : ${MSD_RINGBUF} KB"
fi

# 校验网卡是否存在，提前给出明确提示而不是静默失败
if [ -r /proc/net/dev ]; then
    if ! grep -qE "^\s*${MSD_IFACE}:" /proc/net/dev; then
        log "⚠️  警告: 网卡 '${MSD_IFACE}' 不存在！请用 -e MSD_IFACE=实际网卡名 指定。"
        log "    当前可用网卡: $(awk -F: '/:/{gsub(/ /,"",$1); printf "%s ", $1}' /proc/net/dev)"
    fi
fi

log "启动命令: ${BIN} -c ${CONF} -v"
exec "$BIN" -c "$CONF" -v
