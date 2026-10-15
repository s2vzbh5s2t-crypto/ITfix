# Linux Toolbox

[![Bash](https://img.shields.io/badge/bash-4.x-blue?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)](https://www.kernel.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Linux 服务器交互式运维工具箱，中文界面。

## 功能特性

- **启用 BBR 加速** — 检测内核支持、加载模块、写入并持久化 sysctl 配置，含容器/受限环境预检
- **换源** — 调用 linuxmirrors.cn 官方换源脚本
- **修改 SSH 端口** — 自动备份、端口占用检测、`sshd -t` 校验、失败回滚
- **安装 heki 后端** — 执行 heki 官方安装脚本
- **安装 htop** — 自动识别 apt/dnf/yum/pacman/zypper 包管理器
- **安装 warp-go** — 临时目录下载并校验后执行
- **CDN 边缘 IP 钉定** — EDNS Client Subnet 发现目标地区边缘 IP，ping 测速择优，写入 `/etc/hosts` 覆盖 GeoIP 错判

所有远程操作均有来源提示与二次确认，关键操作带颜色反馈。

## 环境要求

- Linux 系统（支持大多数主流发行版）
- `bash`；远程脚本功能需要 `curl` 或 `wget`
- BBR、htop、SSH 端口修改需要 **root 权限**
- BBR 建议内核 ≥ 4.9（部分内核需加载 `tcp_bbr` 模块）
- CDN 边缘 IP 钉定需要 `dig`（apt: `dnsutils` / yum、dnf: `bind-utils`）和 `ping`，写入时需要 **root 权限**

## 快速使用

使用 root 权限运行：

```bash
bash <(curl -sSL "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")
```

没有 `curl` 时也可用：

```bash
bash <(wget -qO- "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")
```

下载到本地运行：

```bash
curl -sSL -o linux-toolbox.sh "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh"
chmod +x linux-toolbox.sh
sudo bash linux-toolbox.sh
```

## 菜单

```text
========================================
  Linux Toolbox
========================================

1. 启用 BBR 加速
2. 换源
3. 修改 SSH 端口
4. 安装 heki 后端
5. 安装 htop
6. 安装 warp-go
7. CDN 边缘 IP 钉定（gstatic）
0. 退出

请输入选项: _
```

## 功能说明

### 1. 启用 BBR 加速

- 检测 `net.ipv4.tcp_available_congestion_control`，必要时尝试 `modprobe tcp_bbr` 加载模块。
- 先做写入权限探针，OpenVZ/LXC 或容器等无法修改网络 sysctl 的环境会直接给出明确提示并退出。
- 检查 `net.ipv4.tcp_allowed_congestion_control`，若 BBR 未被放行会自动追加，保证 `sysctl` 生效。
- 检查 `fq` 队列算法（`/sys/module/sch_fq`），缺失时可选择**仅启用 BBR、跳过 fq**。
- 写入 `/etc/sysctl.d/bbr.conf` 并立即 `sysctl -p` 应用，重启后依然生效：
  ```text
  net.core.default_qdisc = fq
  net.ipv4.tcp_congestion_control = bbr
  ```

### 2. 换源

执行官方镜像脚本 `https://linuxmirrors.cn/main.sh`（优先 `curl`，缺失时用 `wget` 下载到临时文件后运行）。

### 3. 修改 SSH 端口

- 校验输入为 1-65535，检查目标端口是否已被其他服务占用（`ss`/`netstat`）。
- 自动备份 `sshd_config` 为 `.bak.<时间戳>`。
- 清理重复的 `Port`/`#Port` 行后写入新端口，保证配置干净。
- 写入后执行 `sshd -t` 校验，失败自动恢复备份；再重启 `sshd`/`ssh` 服务。

### 4. 安装 heki 后端

需要 `curl`。下载 heki 官方安装脚本到临时文件后执行，带来源提示与二次确认。

### 5. 安装 htop

自动检测 `apt-get`/`dnf`/`yum`/`pacman`/`zypper` 并安装，`apt` 更新软件源失败时会明确报错。

### 6. 安装 warp-go

需要 `wget`。下载 `warp-go.sh` 到临时目录并校验成功后执行，不污染当前目录。

### 7. CDN 边缘 IP 钉定（gstatic）

VPS 的 IP 归属地（GeoIP）未及时更新时，Google 会把它当作其他国家的 IP，分发远端（如美国）边缘节点，导致高延迟。本功能把 `www.gstatic.com` 钉定到目标地区（默认香港）的低延迟 CDN 边缘 IP：

- **候选发现**：携带 EDNS Client Subnet（`+subnet=43.129.0.0/24`，腾讯云香港段）向 gstatic.com 权威 NS 查询，模拟"目标地区来源"获取该地区的边缘 IP 候选，最多取 8 个。
- **测速择优**：对每个候选 ping 3 次取平均延迟，选延迟最低者（兼容 iputils 与 busybox 的 ping 输出）。
- **安全写入**：写入 `/etc/hosts` 的 `# BEGIN/END cdn-pin` 标记块——写前自动备份为 `hosts.cdn-pin.bak`，临时文件 + 原子 `mv` 替换，写后回读校验失败自动恢复；`flock` 防并发；IP 无变化时跳过写入；自动刷新 systemd-resolved/nscd 缓存。
- **失败兜底**：所有候选 ping 不通时中止不写（禁 ICMP 的 VPS 可设 `CDN_PIN_FORCE=1` 跳过测速强制写入第一个候选）。

菜单子项：预览 / 应用 / 查看状态 / 回滚。功能全部集成在 `linux-toolbox.sh` 单一脚本内（`cdn_pin_` 前缀函数），仅影响标记块，不碰 hosts 其它内容。

局限：只改变域名解析结果，改变不了 BGP 路由；钉定的 IP 变慢或失效后需重新执行应用。换地区只需改 `linux-toolbox.sh` 中 cdn-pin 配置区的 `CDN_PIN_ECS_PREFIX`（可在 bgp.tools 查询各地区机房段）。逻辑回归测试：`bash test-cdn-pin-logic.sh`。

## 安全提示

- **换源、heki 后端安装、warp-go 均会执行远程脚本**，可能修改系统网络或软件源配置，请确认来源可信后再确认执行。
- **修改 SSH 端口前**，请确认防火墙与安全组已放行新端口；修改后先用新端口重新连接并确认可用，再关闭当前 SSH 会话。
- **BBR**：部分旧内核/虚拟化环境可能不支持，脚本会给出提示；无法加载 `fq`/`tcp_bbr` 时需要升级内核或开启对应模块。
- **CDN 边缘 IP 钉定会修改 `/etc/hosts`**（自动备份、原子替换、回滚支持）；钉定的 IP 失效时会导致该域名不可达，异常情况下可用菜单中的回滚或手动删除 `# BEGIN cdn-pin` 与 `# END cdn-pin` 之间的内容恢复。

## License

[MIT](LICENSE)
