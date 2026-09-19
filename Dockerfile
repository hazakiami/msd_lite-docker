# msd_lite — 多阶段构建，静态链接
# msd_lite 是 udpxy 的轻量替代品：资源占用更低、支持 RTP/多线程
FROM ubuntu:latest AS builder

ARG MSD_LITE_BRANCH=master

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl tar gzip \
        build-essential cmake \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# ---- 下载主仓库 ----
RUN set -eux; \
    for url in \
      "https://ghfast.top/https://github.com/rozhuk-im/msd_lite/archive/refs/heads/${MSD_LITE_BRANCH}.tar.gz" \
      "https://gh-proxy.com/https://github.com/rozhuk-im/msd_lite/archive/refs/heads/${MSD_LITE_BRANCH}.tar.gz" \
      "https://codeload.github.com/rozhuk-im/msd_lite/tar.gz/refs/heads/${MSD_LITE_BRANCH}" \
    ; do \
      echo "trying $url"; \
      if curl -4 -fsSL --connect-timeout 15 "$url" -o /tmp/msd.tar.gz && tar tzf /tmp/msd.tar.gz >/dev/null 2>&1; then \
        echo "downloaded: $url"; break; \
      fi; \
    done; \
    tar xzf /tmp/msd.tar.gz --strip-components=1; \
    rm -f /tmp/msd.tar.gz; \
    test -f CMakeLists.txt

# ---- 关键：liblcb 是 git submodule ----
# tarball 下载不包含子模块内容，必须单独获取，否则 CMake 配置会失败：
#   include could not find requested file: src/liblcb/CMakeLists.txt
RUN set -eux; \
    rm -rf src/liblcb; mkdir -p src/liblcb; \
    for url in \
      "https://ghfast.top/https://github.com/rozhuk-im/liblcb/archive/refs/heads/master.tar.gz" \
      "https://gh-proxy.com/https://github.com/rozhuk-im/liblcb/archive/refs/heads/master.tar.gz" \
      "https://codeload.github.com/rozhuk-im/liblcb/tar.gz/refs/heads/master" \
    ; do \
      echo "trying liblcb: $url"; \
      if curl -4 -fsSL --connect-timeout 15 "$url" -o /tmp/liblcb.tar.gz && tar tzf /tmp/liblcb.tar.gz >/dev/null 2>&1; then \
        echo "downloaded liblcb: $url"; \
        tar xzf /tmp/liblcb.tar.gz -C src/liblcb --strip-components=1; \
        break; \
      fi; \
    done; \
    rm -f /tmp/liblcb.tar.gz; \
    test -f src/liblcb/CMakeLists.txt

# ---- 静态编译 ----
# 注意：CMakeLists 里 try_linker_flag 会自动探测并追加 -pie/-z relro 等加固参数，
# 与 -static 冲突时会导致构建失败，所以显式关闭 PIE 并清空链接加固标志。
RUN set -eux; \
    mkdir -p build && cd build; \
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_EXE_LINKER_FLAGS="-static -no-pie" \
      -DCMAKE_C_FLAGS="-static -no-pie -fno-pie" \
    && make -j"$(nproc)" \
    && strip --strip-all src/msd_lite \
    && mkdir -p /out \
    && cp -f src/msd_lite /out/msd_lite \
    && ls -l /out/msd_lite

# ============================================================
# 运行镜像
# ============================================================
FROM alpine:latest

LABEL org.opencontainers.image.title="msd_lite" \
      org.opencontainers.image.description="Multi stream daemon lite — lightweight UDP/RTP multicast to HTTP relay" \
      org.opencontainers.image.source="https://github.com/rozhuk-im/msd_lite" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

RUN set -eux; \
    addgroup -S msd; \
    adduser -S -G msd -H -s /sbin/nologin msd; \
    mkdir -p /etc/msd_lite

COPY --from=builder /out/msd_lite /usr/local/bin/msd_lite

ENV MSD_PORT=7088 \
    MSD_IFACE=eth0 \
    MSD_LOG_LEVEL=6 \
    MSD_PRECACHE=4096 \
    MSD_RINGBUF=1024 \
    MSD_THREADS=1 \
    MSD_SNDBUF=512 \
    MSD_SNDLOWAT=64 \
    MSD_RCVBUF=512 \
    MSD_RCVLOWAT=48 \
    MSD_RCVTIMEOUT=2 \
    MSD_MULTICAST_PATH=no

COPY entrypoint.sh /entrypoint.sh
COPY msd_lite.conf.template /etc/msd_lite/msd_lite.conf.template
RUN chmod +x /entrypoint.sh

# 健康检查：请求 /stat 统计页
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${MSD_PORT}/stat" || exit 1

EXPOSE 7088/tcp

ENTRYPOINT ["/entrypoint.sh"]
