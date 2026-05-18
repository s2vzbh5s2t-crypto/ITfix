# Linux Toolbox

Linux 服务器交互式运维脚本，默认中文界面，支持切换英文。

## 功能

- 启用 BBR 加速
- 执行 Linux 换源脚本
- 修改 SSH 端口
- 安装 heki 后端
- 中英文切换

## 快速运行

建议使用 root 权限运行：

```bash
bash <(curl -sSL "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")
```

运行后按菜单编号选择功能：

```text
1. 启用 BBR 加速
2. 换源
3. 修改 SSH 端口
4. 安装 heki 后端
5. 中英文切换
0. 退出
```

## 说明

- BBR 会写入 `/etc/sysctl.d/bbr.conf`，配置 `net.core.default_qdisc=fq` 和 `net.ipv4.tcp_congestion_control=bbr`。
- BBR 会检查内核是否支持 `bbr`，必要时尝试加载 `tcp_bbr` 模块。
- 换源功能会执行 `https://linuxmirrors.cn/main.sh`。
- 修改 SSH 端口会编辑 `/etc/ssh/sshd_config`，并为 SSH 配置生成 `.bak` 备份。
- 安装 heki 后端会执行 `bash <(curl -Ls https://raw.githubusercontent.com/hekicore/heki/master/install.sh)`。
- 换源功能如果没有 `curl`，会尝试使用 `wget` 下载远程脚本；安装 heki 后端需要 `curl`。

## 注意事项

- 换源、heki 后端安装和 SSH 端口修改可能影响服务器连接，请确认脚本来源、端口放行和回滚方式后再执行。
- 修改 SSH 端口后，请先用新端口连接成功，再关闭当前 SSH 会话。
- 部分系统或内核版本可能不支持 BBR，需要升级内核或启用对应模块。
