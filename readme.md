# Linux Toolbox

[![Bash](https://img.shields.io/badge/bash-4.x-blue?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)](https://www.kernel.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Linux 服务器交互式运维工具箱，默认中文界面，支持一键切换英文（`LANGUAGE=en` 可默认英文）。

## 功能特性

- **启用 BBR 加速** — 检测内核支持、加载模块、写入并持久化 sysctl 配置，含容器/受限环境预检
- **换源** — 调用 linuxmirrors.cn 官方换源脚本
- **修改 SSH 端口** — 自动备份、端口占用检测、`sshd -t` 校验、失败回滚
- **安装 heki 后端** — 执行 heki 官方安装脚本
- **安装 htop** — 自动识别 apt/dnf/yum/pacman/zypper 包管理器
- **安装 warp-go** — 临时目录下载并校验后执行
- **中英文切换** — 运行时切换，或通过环境变量 `LANGUAGE=en` 默认英文

所有远程操作均有来源提示与二次确认，关键操作带颜色反馈。

## 环境要求

- Linux 系统（支持大多数主流发行版）
- `bash`；远程脚本功能需要 `curl` 或 `wget`
- BBR、htop、SSH 端口修改需要 **root 权限**
- BBR 建议内核 ≥ 4.9（部分内核需加载 `tcp_bbr` 模块）

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

默认英文界面：

```bash
LANGUAGE=en bash <(curl -sSL "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")
```

## 菜单

```text
========================================
  Linux Toolbox
========================================
当前语言: zh

1. 启用 BBR 加速
2. 换源
3. 修改 SSH 端口
4. 安装 heki 后端
5. 安装 htop
6. 安装 warp-go
7. 中英文切换
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

### 7. 中英文切换

运行时在菜单选择语言即时生效；也可以预设环境变量 `LANGUAGE=en` 默认英文。

## 安全提示

- **换源、heki 后端安装、warp-go 均会执行远程脚本**，可能修改系统网络或软件源配置，请确认来源可信后再确认执行。
- **修改 SSH 端口前**，请确认防火墙与安全组已放行新端口；修改后先用新端口重新连接并确认可用，再关闭当前 SSH 会话。
- **BBR**：部分旧内核/虚拟化环境可能不支持，脚本会给出提示；无法加载 `fq`/`tcp_bbr` 时需要升级内核或开启对应模块。

## License

[MIT](LICENSE)
