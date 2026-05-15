# Linux Toolbox

一个面向 Linux 服务器的交互式脚本入口。主脚本保留本地启用 BBR、Linux 换源、修改 SSH 端口和中英文切换。

脚本默认使用中文界面，也支持在菜单中切换为英文。BBR 功能会在本地写入 `/etc/sysctl.d/bbr.conf`，不再调用远程 BBR 脚本。

## 功能

- 本地启用 BBR 加速
- 执行 Linux 换源脚本
- 修改 SSH 端口
- 中英文界面切换

## 快速执行

在 root 环境下直接从 GitHub 拉取并运行主入口脚本：

```bash
bash <(curl -sSL "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")
```

运行后根据菜单输入对应编号即可。

## 文件

- `linux-toolbox.sh`：主脚本入口
- `readme.md`：项目说明文档

## 菜单说明

```text
1. 启用 BBR 加速
2. 换源
3. 修改 SSH 端口
4. 中英文切换
0. 退出
```

## 引用脚本源

主入口脚本：

| 名称 | 地址 | 直接执行 |
| --- | --- | --- |
| Linux Toolbox | `https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh` | `bash <(curl -sSL "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")` |

菜单引用的远程脚本：

| 菜单项 | 语言 | 地址 | 直接执行 |
| --- | --- | --- | --- |
| 换源 | 通用 | `https://linuxmirrors.cn/main.sh` | `bash <(curl -sSL "https://linuxmirrors.cn/main.sh")` |

如果系统没有 `curl`，主脚本内部会尝试使用 `wget -qO- URL | bash` 作为备用方式运行远程脚本。

## 权限说明

脚本默认在 root 环境下运行。BBR 加速会写入 `/etc/sysctl.d/bbr.conf` 并应用 `net.core.default_qdisc=fq`、`net.ipv4.tcp_congestion_control=bbr`。Linux 换源会从远程地址下载并交给 `bash` 执行，可能会修改系统软件源配置。

修改 SSH 端口会编辑 `/etc/ssh/sshd_config`。脚本会先备份原配置，写入新端口后执行 `sshd -t` 检查配置，并尝试重启 `ssh` 或 `sshd` 服务。

## BBR 配置说明

BBR 功能只写入最小化、普适型配置，不包含激进 TCP/NAT 调优参数：

```conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

`net.core.default_qdisc=fq` 用于启用 `fq` 队列调度，配合 BBR 做流量 pacing。

`net.ipv4.tcp_congestion_control=bbr` 用于启用 BBR 拥塞控制，适合跨境、高延迟、传统 `cubic` 吞吐不佳的 TCP 链路。

脚本会在写入前检查当前状态和内核是否提供 `bbr`，必要时尝试加载 `tcp_bbr` 模块。如果 `/etc/sysctl.d/bbr.conf` 已存在，会先生成 `.bak` 备份，再覆盖写入新配置。

## 线路优化建议

面向中国连接海外的场景，线路质量通常比 BBR 更重要。推荐优先级：

```text
线路质量 > 协议选择 > 拥塞控制算法 > MTU/MSS > 系统参数微调
```

常见线路选择：

- 电信优先考虑 `CN2 GIA`
- 联通优先考虑 `AS9929` 或优质 `4837`
- 移动优先考虑 `CMI`
- 多运营商场景优先考虑三网优化、优质 BGP、香港/日本/新加坡入口

如果海外直连质量差，可以考虑中转：

```text
用户 -> 香港/日本/新加坡中转 -> 海外落地
```

BBR 最适合高延迟、跨境 TCP、带宽跑不满、轻中度丢包的链路。它不能解决绕路、晚高峰严重拥塞、运营商限速、UDP 被限速或节点线路本身质量差的问题。

除 BBR 外，可根据实际情况优化：

- 调整 MTU/MSS，解决部分网页半开、TLS 握手卡住、测速不稳定问题
- 根据网络质量选择 TCP/TLS 或 UDP/QUIC 类协议
- 避免 TCP over TCP，弱网下容易放大卡顿
- 谨慎使用多路复用，跨境丢包时可能出现“一卡全卡”
- 准备多节点备用，晚高峰按实际质量切换

不建议默认加入过于激进的 sysctl 参数，例如 `tcp_tw_recycle`、`tcp_fin_timeout=2`、过低的 `tcp_max_tw_buckets` 或异常大的 `somaxconn`。这些参数对线路体验帮助有限，反而可能引入连接异常。

## 依赖

脚本依赖以下命令：

- `bash`：运行主脚本和换源远程脚本
- `sysctl`：读取和应用 BBR 内核参数
- `modprobe`：可选，用于尝试加载 `tcp_bbr` 模块
- `grep`、`sed`：读取和修改 SSH 配置
- `curl` 或 `wget`：下载远程脚本

## 注意事项

- 运行换源远程脚本前，建议先确认脚本来源可信。
- 换源远程脚本可能修改系统配置，请根据实际环境评估后使用。
- 如果服务器由云厂商、面板或其他自动化工具管理，可能存在配置覆盖情况。
- 建议在生产环境执行前先在测试环境验证。
- 部分系统或内核版本可能不支持 BBR，需升级内核或启用对应模块。
- 修改 SSH 端口前，请确认防火墙和云厂商安全组已经放行新端口。
- 修改 SSH 端口后，请先用新端口重新连接成功，再关闭当前 SSH 会话。

## 常见问题

### BBR 加速失败怎么办？

确认当前环境是否为 root，并检查内核是否支持 BBR：

```bash
sysctl net.ipv4.tcp_available_congestion_control
```

如果输出不包含 `bbr`，通常需要升级内核或启用 `tcp_bbr` 模块。

### 换源执行失败怎么办？

确认当前系统可以访问对应远程脚本地址，并检查当前环境是否为 root。

### 修改 SSH 端口后连不上怎么办？

确认防火墙和安全组是否放行了新端口。如果仍保留当前 SSH 会话，可以检查 `/etc/ssh/sshd_config` 和脚本生成的 `.bak` 备份文件。

## 免责声明

本工具主要作为远程运维脚本入口。BBR 功能会修改本机内核网络参数，换源远程脚本可能修改软件源配置。请在理解影响后使用，由此造成的服务异常、连接中断或性能变化需要自行评估和处理。
