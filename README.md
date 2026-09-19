# msd_lite — 轻量级 IPTV 组播转 HTTP 中继

把 **msd_lite（Multi stream daemon lite）** 编译打包为极简 Docker 镜像。用于把运营商 IPTV 的 **UDP / RTP 组播流** 转换成 **HTTP 单播流**，让手机、平板、播放器（VLC / Kodi / 电视盒子）在内网任意位置直接播放。

`msd_lite` 是经典工具 `udpxy` 的**轻量替代品**：资源占用更低、原生支持 RTP、支持多线程与预缓存。适合只需要「组播转 HTTP」这一件事、追求低资源占用的场景。

- 上游项目：[rozhuk-im/msd_lite](https://github.com/rozhuk-im/msd_lite)（GPL-3.0-or-later）
- 本镜像特点：**静态链接**、14.2 MB、多阶段构建、内置健康检查、环境变量即配即用

---

## 镜像信息

| 项目 | 值 |
|---|---|
| 镜像 | `hazaki/msd_lite:latest` |
| msd_lite 版本 | **1.11.0** |
| 镜像大小 | **12.6 MB** |
| 构建基础镜像 | `alpine:3.21`（musl，apk 源使用清华镜像） |
| 运行基础镜像 | `alpine:3.21`（与构建阶段统一，均为 musl） |
| 链接方式 | **静态链接**（无动态库依赖，可跨发行版运行） |
| 二进制大小 | 276,224 字节（270 KiB，strip 后） |
| 暴露端口 | **7088/tcp** |
| 架构 | `linux/amd64` |
| 健康检查 | 内置，探测 `/stat` 统计页 |
| 许可证 | GPL-3.0-or-later |

---

## 快速开始

### docker run

```bash
docker run -d \
  --name msd_lite \
  --network host \
  -e MSD_PORT=7088 \
  -e MSD_IFACE=eth0 \
  --restart unless-stopped \
  hazaki/msd_lite:latest
```

### docker-compose

```yaml
services:
  msd_lite:
    image: hazaki/msd_lite:latest
    container_name: msd_lite
    restart: unless-stopped
    # 必须使用 host 网络：容器需要加入宿主机的组播组
    network_mode: host
    environment:
      MSD_PORT: "7088"
      # ⚠️ 改成实际接收 IPTV 组播的网卡名，用 `ip a` 查看
      MSD_IFACE: "eth0"
      MSD_PRECACHE: "4096"
      MSD_RINGBUF: "1024"
```

启动后即可拉流：

```bash
curl -o channel.ts http://127.0.0.1:7088/udp/239.255.42.99:1234
```

---

## 播放地址

假设服务器 IP 为 `192.168.1.10`：

| 类型 | 地址 |
|---|---|
| UDP 组播 | `http://192.168.1.10:7088/udp/<组播地址>:<端口>` |
| RTP 组播 | `http://192.168.1.10:7088/rtp/<组播地址>:<端口>` |
| 统计页 | `http://192.168.1.10:7088/stat` |

示例：

```
http://192.168.1.10:7088/udp/239.255.42.99:1234     # UDP 组播
http://192.168.1.10:7088/rtp/239.255.42.99:1234     # RTP 组播
http://192.168.1.10:7088/stat                       # 运行统计
```

在 VLC 中：**媒体 → 打开网络串流**，粘贴上面的地址即可。

---

## 环境变量

程序参数通过环境变量传入，入口脚本会自动渲染 XML 配置到 `/etc/msd_lite/msd_lite.conf`。

| 变量 | 默认值 | 单位 | 说明 |
|---|---|---|---|
| `MSD_PORT` | `7088` | — | HTTP 监听端口 |
| `MSD_IFACE` | `eth0` | — | **接收组播的网卡名**（必须真实存在，不能填 IP） |
| `MSD_LOG_LEVEL` | `6` | — | 日志级别 `0`(EMERG) ~ `7`(DEBUG) |
| `MSD_PRECACHE` | `4096` | **KB** | 预缓存，客户端接入后先缓冲再播放 |
| `MSD_RINGBUF` | `1024` | **KB** | 环形缓冲区大小，建议 ≥ `MSD_PRECACHE` |
| `MSD_THREADS` | `1` | — | 线程数 |
| `MSD_SNDBUF` | `512` | **字节** | 客户端 socket 发送缓冲 |
| `MSD_SNDLOWAT` | `64` | **字节** | 发送块大小，必须为 4 的倍数 |
| `MSD_RCVBUF` | `512` | **字节** | 组播接收 socket 缓冲 |
| `MSD_RCVLOWAT` | `48` | **字节** | 接收低水位 |
| `MSD_RCVTIMEOUT` | `2` | **秒** | 超过该时间无数据则销毁流；`0` = 不检查 |

> ⚠️ **单位陷阱**：`MSD_PRECACHE` / `MSD_RINGBUF` 单位是 **KB**（程序内部 ×1024），
> 而 `MSD_SNDBUF` / `MSD_RCVBUF` 等单位是**字节**。混淆会导致参数被错误钳制。
>
> ⚠️ 镜像里还声明了 `MSD_MULTICAST_PATH=no`，但入口脚本与配置模板**均未使用**它（历史遗留），
> 设置该变量不会有任何效果。

---

## 三种使用方式

### 方式一：环境变量（推荐）

见上方快速开始。入口脚本会把 `/etc/msd_lite/msd_lite.conf.template` 渲染成 `/etc/msd_lite/msd_lite.conf`。

### 方式二：挂载自己的配置文件

```bash
docker run -d --name msd_lite --network host \
  -v /my/msd_lite.conf:/etc/msd_lite/msd_lite.conf:ro \
  hazaki/msd_lite:latest -c /etc/msd_lite/msd_lite.conf
```

检测到已有的 `/etc/msd_lite/msd_lite.conf` 时，入口脚本会**跳过渲染、直接使用**该文件。

### 方式三：透传 msd_lite 原生参数

当第一个参数以 `-` 开头时，入口脚本会原样透传给 msd_lite 二进制：

```bash
docker run -d --name msd_lite --network host \
  hazaki/msd_lite:latest -c /path/conf -v

docker run --rm --network host hazaki/msd_lite:latest -h    # 查看原生帮助
```

---

## 重要注意事项

### 1. 必须使用 host 网络

msd_lite 依靠 **IGMP 组播**接收 IPTV 流，Docker bridge 网络无法正常收发组播。
必须 `--network host`（compose 里用 `network_mode: host`）。

### 2. 网卡名必须写对

`MSD_IFACE` 要填**实际接收 IPTV 组播的物理网卡名**（用 `ip a` 查看），如 `eth0`、`ens33`。
源码用 `if_nametoindex()` 转换网卡名，**写 IP 地址会导致组播加入失败**。
入口脚本会检查网卡是否存在，不存在时打印警告并列出当前可用网卡。

### 3. 测试时码率必须足够高

源码在发送数据时若单次可用数据量小于发送块下限，会**直接跳过不发送**。
用低码率测试包会看到「HTTP 200、body 为 0 字节」的现象，容易误判为故障。
✅ **正确测法**：模拟真实 IPTV 码率（1.5 ~ 8 Mbps），可稳定接收数 MB 数据。

### 4. 拉流开头的解码警告是正常的

用 `ffmpeg` / `ffprobe` 校验时，开头常会打印：

```
[h264 @ ...] non-existing PPS 0 referenced
[h264 @ ...] no frame!
```

这是 **HTTP 客户端从流中途接入**、尚未遇到第一个关键帧（含 SPS/PPS）所致，属正常现象。
抽帧时用 `-ss` 跳过前几秒即可正常解码 —— 实测 `-ss 8` 可稳定抽帧。

### 5. 组播源需先通

msd_lite 只做转发，前提是**服务器本身能收到上游 IPTV 组播**。
若 `/udp/...` 请求一直挂起无数据，请先在宿主机上确认能收到该组播组（`tcpdump -i eth0 -n udp port <端口>`）。

### 6. 容器以 root 运行

镜像内创建了 `msd` 非特权用户，但**未切换**（Dockerfile 无 `USER` 指令），
容器默认仍以 root 运行。如需降权可自行加 `--user`。

---

## 运维命令

```bash
docker logs -f msd_lite                                     # 查看日志
docker inspect msd_lite --format '{{.State.Health.Status}}' # 健康状态
curl -s http://127.0.0.1:7088/stat                          # 统计信息
ss -tln | grep 7088                                         # 监听检查
docker restart msd_lite                                     # 重启
```

`/stat` 输出示例：

```
Server: Multi stream daemon lite 1.11.0 (Sep 14 2026 01:56:28)
running time: 0+00:00:32
connections online: 1
timeouts: 0
errors: 0
HTTP errors: 0
unhandled requests (404): 0
requests total: 3

Per Thread stat
Thread: 0 @ cpu -1
Stream hub count: 1
Clients count: 1
Rate in: 1 mbps
Rate out: 1 mbps
```

---

## 验证记录

在 Ubuntu 26.04 / Docker 29.8.1 上实测（ffmpeg 构造 H.264 640x480 @1.5 Mbps 真实 MPEG-TS 流）：

| 测试项 | 结果 |
|---|---|
| 容器启动 | ✅ `Up (healthy)`，日志 `msd_lite 1.11.0: started!` |
| 健康检查 `/stat` | ✅ HTTP 200 |
| `/udp/<组播>:<端口>` 拉流 | ✅ HTTP 200，5,136,724 字节 / 25 秒，解码 **478 帧 @640x480** |
| `/rtp/<组播>:<端口>` 拉流 | ✅ HTTP 200，3,905,136 字节，解码 **351 帧 @640x480** |
| 抽帧验证 | ✅ 成功导出 51,719 字节 PNG |
| `/stat` 统计页 | ✅ `errors: 0` / `HTTP errors: 0` / `404: 0` |
| 不存在的路径 | ✅ HTTP 404 |

---

## 镜像传输（离线部署）

```bash
# 源机导出
docker save hazaki/msd_lite:latest -o msd_lite.tar

# 目标机导入
docker load -i msd_lite.tar
```

---

## 已知事项

- **liblcb 是 git submodule**：源码 tarball 不包含子模块内容，直接构建会报
  `include could not find requested file: src/liblcb/CMakeLists.txt`。
  Dockerfile 已单独下载 liblcb 并填入 `src/liblcb/`。
- **CMake 需显式关闭 PIE**：CMakeLists 内部 `try_linker_flag` 会自动追加 `-pie` / `-z relro`，
  与 `-static` 冲突，因此构建时显式传入 `-no-pie`。
- 源码下载使用三级镜像代理 fallback（`ghfast.top` → `gh-proxy.com` → `codeload.github.com`），
  网络受限环境下也能构建成功。

---

## 相关镜像

| 镜像 | 说明 |
|---|---|
| `hazaki/msd_lite`（本镜像） | 轻量版，资源占用低，仅基础组播转 HTTP |
| `hazaki/msd` | 完整版，额外支持频道列表 / MPEG2-TS PID 过滤 / 零拷贝 / HTTP 源转发 |
| `hazaki/udpxy` | 经典 UDP-to-HTTP 中继，兼容老配置与老客户端 |

### msd_lite vs udpxy 怎么选？

| 特性 | udpxy | **msd_lite** |
|---|---|---|
| 配置方式 | 纯命令行参数 | XML（也可用环境变量） |
| RTP 支持 | 需显式配置 | ✅ 原生 |
| 多线程 | ❌ | ✅ |
| 预缓存 | 有限 | ✅ 可调 |
| 资源占用 | 较高 | ✅ 更低 |
| 统计页 | `/status` | `/stat` |

> 新部署建议优先选 `msd_lite`；已有 udpxy 配置或客户端兼容性要求高时选 `udpxy`。

---

## 许可证与致谢

本镜像是 [rozhuk-im/msd_lite](https://github.com/rozhuk-im/msd_lite) 的容器化封装，
遵循上游 **GPL-3.0-or-later** 许可证。感谢 Rozhuk Ivan 的出色工作。

> msd_lite 仅做组播流到 HTTP 的协议转换，**不提供、不包含任何流媒体内容**。
> 请确保你转发的内容来源合法，并遵守当地法律法规。
