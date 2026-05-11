# Linux Toolbox

一个面向 Linux 服务器的交互式脚本集合入口。主脚本负责展示菜单、切换语言、查看基础系统信息，并按菜单调用不同的远程运维脚本。

脚本默认使用中文界面，也支持在菜单中切换为英文。部分远程脚本会根据当前语言自动选择中文或英文入口。

## 功能

- 查看系统信息：系统版本、内核版本、CPU 架构、主机名、运行时间
- 查看资源使用情况：内存占用、磁盘空间
- 查看端口占用：支持输入指定端口，也可以查看全部监听端口
- 查看 BBR 状态：检查当前队列算法、拥塞控制算法以及 `tcp_bbr` 模块状态
- 脚本集合：通过菜单运行常用远程脚本
- 中英文界面切换

## 快速执行

直接从 GitHub 拉取并运行主入口脚本：

```bash
bash <(curl -sSL "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")
```

如果需要执行 BBR 加速、Linux 换源等可能修改系统配置的远程脚本，建议使用 root 权限：

```bash
sudo bash -c 'bash <(curl -sSL "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")'
```

## 本地运行

赋予执行权限：

```bash
chmod +x linux-toolbox.sh
```

运行脚本：

```bash
./linux-toolbox.sh
```

运行后根据菜单输入对应编号即可。

## 文件

- `linux-toolbox.sh`：主脚本入口
- `readme.md`：项目说明文档

## 菜单说明

```text
1. 系统信息
2. 资源使用情况
3. 端口占用查看
4. BBR 状态查看
5. 脚本集合
9. 切换语言
0. 退出
```

进入 `脚本集合` 后可以继续选择具体脚本。目前包含：

```text
1. BBR 加速脚本
2. Linux 换源脚本
0. 返回主菜单
```

## 引用脚本源

主入口脚本：

| 名称 | 地址 | 直接执行 |
| --- | --- | --- |
| Linux Toolbox | `https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh` | `bash <(curl -sSL "https://raw.githubusercontent.com/s2vzbh5s2t-crypto/ITfix/main/linux-toolbox.sh")` |

脚本集合引用的远程脚本：

| 菜单项 | 语言 | 地址 | 直接执行 |
| --- | --- | --- | --- |
| BBR 加速脚本 | 中文 | `https://scripts.zeroteam.top/NATPlugin/tcp_zhcn.sh` | `bash <(curl -sSL "https://scripts.zeroteam.top/NATPlugin/tcp_zhcn.sh")` |
| BBR 加速脚本 | 英文 | `https://scripts.zeroteam.top/NATPlugin/tcp.sh` | `bash <(curl -sSL "https://scripts.zeroteam.top/NATPlugin/tcp.sh")` |
| Linux 换源脚本 | 通用 | `https://linuxmirrors.cn/main.sh` | `bash <(curl -sSL "https://linuxmirrors.cn/main.sh")` |

如果系统没有 `curl`，主脚本内部会尝试使用 `wget -qO- URL | bash` 作为备用方式运行脚本集合中的远程脚本。

## 权限说明

大部分查看类功能不需要 root 权限。

`脚本集合` 中的远程脚本会从远程地址下载并交给 `bash` 执行。远程脚本可能会修改系统网络、内核参数或资源限制配置，因此通常需要 root 权限。

## 添加新脚本

后续如果要加入更多脚本，可以在 `linux-toolbox.sh` 中新增一个调用函数，然后把它挂到 `show_script_collection` 菜单里。

推荐新增脚本时使用现有的 `run_remote_script` 入口，这样可以复用语言选择、下载方式和执行确认逻辑。

## 依赖

脚本使用常见 Linux 系统命令，通常无需额外安装。部分功能依赖以下命令：

- `free`：查看内存使用情况
- `df`：查看磁盘使用情况
- `ss` 或 `netstat`：查看端口占用
- `sysctl`：读取内核参数
- `lsmod`：检查内核模块状态
- `curl` 或 `wget`：下载远程脚本

如果某个命令不存在，脚本会给出提示，对应功能可能无法完整显示。

## 注意事项

- 运行远程脚本前，建议先确认脚本来源可信。
- 远程脚本可能修改系统配置，请根据实际环境评估后使用。
- 如果服务器由云厂商、面板或其他自动化工具管理，可能存在配置覆盖情况。
- 建议在生产环境执行前先在测试环境验证。
- 部分系统或内核版本可能不支持 BBR，需升级内核或启用对应模块。

## 常见问题

### BBR 加速脚本运行后没有生效怎么办？

先在主菜单中选择 `BBR 状态查看` 检查当前状态。如果 `tcp_bbr` 模块未加载，可以尝试重启系统后再次查看。

### 提示需要 root 权限怎么办？

使用 `sudo ./linux-toolbox.sh` 或切换到 root 用户后运行脚本。

### 端口占用查询没有结果怎么办？

确认目标端口是否处于监听状态。脚本优先使用 `ss`，如果系统没有 `ss` 会尝试使用 `netstat`。

## 免责声明

本工具主要作为远程运维脚本入口。远程脚本可能修改系统网络、内核参数和资源限制配置。请在理解影响后使用，由此造成的服务异常、连接中断或性能变化需要自行评估和处理。
