# Linux Toolbox

一个面向 Linux 服务器的交互式脚本入口。主脚本只保留 BBR 加速、Linux 换源和中英文切换。

脚本默认使用中文界面，也支持在菜单中切换为英文。执行 BBR 加速时会根据当前语言自动选择中文或英文脚本。

## 功能

- 执行 BBR 加速脚本
- 执行 Linux 换源脚本
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
1. 执行 BBR 加速
2. 换源
3. 中英文切换
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
| 执行 BBR 加速 | 中文 | `https://scripts.zeroteam.top/NATPlugin/tcp_zhcn.sh` | `bash <(curl -sSL "https://scripts.zeroteam.top/NATPlugin/tcp_zhcn.sh")` |
| 执行 BBR 加速 | 英文 | `https://scripts.zeroteam.top/NATPlugin/tcp.sh` | `bash <(curl -sSL "https://scripts.zeroteam.top/NATPlugin/tcp.sh")` |
| 换源 | 通用 | `https://linuxmirrors.cn/main.sh` | `bash <(curl -sSL "https://linuxmirrors.cn/main.sh")` |

如果系统没有 `curl`，主脚本内部会尝试使用 `wget -qO- URL | bash` 作为备用方式运行远程脚本。

## 权限说明

脚本默认在 root 环境下运行。远程脚本会从远程地址下载并交给 `bash` 执行，BBR 加速和 Linux 换源可能会修改系统网络、内核参数、软件源或资源限制配置。

## 依赖

脚本依赖以下命令：

- `bash`：运行主脚本和远程脚本
- `curl` 或 `wget`：下载远程脚本

## 注意事项

- 运行远程脚本前，建议先确认脚本来源可信。
- 远程脚本可能修改系统配置，请根据实际环境评估后使用。
- 如果服务器由云厂商、面板或其他自动化工具管理，可能存在配置覆盖情况。
- 建议在生产环境执行前先在测试环境验证。
- 部分系统或内核版本可能不支持 BBR，需升级内核或启用对应模块。

## 常见问题

### BBR 加速或换源执行失败怎么办？

确认当前系统可以访问对应远程脚本地址，并检查当前环境是否为 root。

## 免责声明

本工具主要作为远程运维脚本入口。远程脚本可能修改系统网络、内核参数、软件源和资源限制配置。请在理解影响后使用，由此造成的服务异常、连接中断或性能变化需要自行评估和处理。
