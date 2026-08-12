#!/usr/bin/env bash

set -o pipefail

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
RESET='\033[0m'

print_red() { printf "%b\n" "${RED}$1${RESET}"; }
print_green() { printf "%b\n" "${GREEN}$1${RESET}"; }
print_yellow() { printf "%b\n" "${YELLOW}$1${RESET}"; }
print_blue() { printf "%b\n" "${BLUE}$1${RESET}"; }
print_cyan() { printf "%b\n" "${CYAN}$1${RESET}"; }

pause() {
    printf "\n%s" "按回车键继续..."
    read -r _
}

confirm() {
    local prompt="$1"
    local answer

    printf "%s [y/N]: " "$prompt"
    read -r answer
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

run_remote_script() {
    clear
    local title="$1"
    local script_url="$2"

    print_cyan "$title"

    printf "%s: %s\n" "即将运行远程脚本" "$script_url"
    print_yellow "远程脚本可能会修改系统网络配置，请确认来源可信后继续。"
    confirm "确认继续？" || return

    local tmp_script=""
    if command -v curl >/dev/null 2>&1; then
        tmp_script="$(mktemp)" || { print_red "创建临时文件失败。"; pause; return; }
        if ! curl -fsSL "$script_url" -o "$tmp_script"; then
            print_red "远程脚本下载失败：$script_url"
            rm -f "$tmp_script"
            pause
            return
        fi
    elif command -v wget >/dev/null 2>&1; then
        tmp_script="$(mktemp)" || { print_red "创建临时文件失败。"; pause; return; }
        if ! wget -qO "$tmp_script" "$script_url"; then
            print_red "远程脚本下载失败：$script_url"
            rm -f "$tmp_script"
            pause
            return
        fi
    else
        print_red "当前系统缺少 curl/wget，无法下载远程脚本。"
        pause
        return
    fi

    bash "$tmp_script"
    local rc=$?
    rm -f "$tmp_script"
    if [ "$rc" -ne 0 ]; then
        print_red "远程脚本执行失败，请检查上方输出。"
    fi

    pause
}

run_bbr_acceleration_script() {
    clear
    local config="/etc/sysctl.d/bbr.conf"
    local current_qdisc
    local current_congestion
    local available_congestion
    local allowed_congestion
    local use_fq=1

    print_cyan "启用 BBR 加速"

    if [ "$EUID" -ne 0 ]; then
        print_red "请使用 root 权限运行此功能。"
        pause
        return
    fi

    if ! command -v sysctl >/dev/null 2>&1; then
        print_red "当前系统缺少 sysctl，无法配置 BBR。"
        pause
        return
    fi

    current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    current_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    available_congestion="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    allowed_congestion="$(sysctl -n net.ipv4.tcp_allowed_congestion_control 2>/dev/null || true)"

    printf "当前队列算法: %s\n" "${current_qdisc:-unknown}"
    printf "当前拥塞控制: %s\n" "${current_congestion:-unknown}"
    printf "可用拥塞控制: %s\n" "${available_congestion:-unknown}"
    printf "允许拥塞控制: %s\n" "${allowed_congestion:-unknown}"

    if [ -n "$current_congestion" ] && ! sysctl -w net.ipv4.tcp_congestion_control="$current_congestion" >/dev/null 2>&1; then
        print_red "当前环境无法修改网络相关 sysctl 参数（常见于 OpenVZ/LXC 或容器环境），无法启用 BBR。"
        pause
        return
    fi

    if ! printf '%s\n' "$available_congestion" | grep -qw bbr; then
        if command -v modprobe >/dev/null 2>&1; then
            modprobe tcp_bbr 2>/dev/null || true
            available_congestion="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
        fi

        if ! printf '%s\n' "$available_congestion" | grep -qw bbr; then
            print_red "当前内核未提供 BBR，可能需要升级内核或启用 tcp_bbr 模块。"
            pause
            return
        fi
    fi

    if [ "$current_qdisc" != "fq" ]; then
        if [ ! -d /sys/module/sch_fq ]; then
            command -v modprobe >/dev/null 2>&1 && modprobe sch_fq 2>/dev/null || true
        fi

        if [ ! -d /sys/module/sch_fq ]; then
            print_yellow "当前内核缺少 fq 队列算法（可能需要加载 sch_fq 模块或升级内核）。"
            if confirm "是否仅启用 BBR，跳过 fq 队列设置？"; then
                use_fq=0
            else
                pause
                return
            fi
        fi
    fi

    if [ "$use_fq" -eq 1 ]; then
        print_yellow "将写入配置到 /etc/sysctl.d/bbr.conf：net.core.default_qdisc=fq，net.ipv4.tcp_congestion_control=bbr。"
    else
        print_yellow "将写入配置到 /etc/sysctl.d/bbr.conf：net.ipv4.tcp_congestion_control=bbr（跳过 fq 队列设置）。"
    fi
    confirm "确认继续？" || return

    if ! mkdir -p "$(dirname "$config")"; then
        print_red "创建 sysctl 配置目录失败。"
        pause
        return
    fi

    if ! {
        if [ -n "$allowed_congestion" ] && ! printf '%s\n' "$allowed_congestion" | grep -qw bbr; then
            printf 'net.ipv4.tcp_allowed_congestion_control = %s bbr\n' "$allowed_congestion"
        fi
        if [ "$use_fq" -eq 1 ]; then
            printf 'net.core.default_qdisc = fq\n'
        fi
        printf 'net.ipv4.tcp_congestion_control = bbr\n'
    } >"$config"; then
        print_red "写入 BBR 配置失败。"
        pause
        return
    fi

    if ! sysctl -p "$config"; then
        print_red "应用 BBR 配置失败，请检查系统是否支持相关参数。"
        pause
        return
    fi

    current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    current_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"

    printf "当前队列算法: %s\n" "${current_qdisc:-unknown}"
    printf "当前拥塞控制: %s\n" "${current_congestion:-unknown}"

    if [ "$current_congestion" = "bbr" ] && { [ "$use_fq" -eq 0 ] || [ "$current_qdisc" = "fq" ]; }; then
        print_green "BBR 已启用并写入持久配置：$config"
    else
        print_yellow "配置已写入，但当前状态未完全匹配，可能需要重启或检查内核支持。"
    fi

    pause
}

run_change_mirror_script() {
    run_remote_script "Linux 换源脚本" "https://linuxmirrors.cn/main.sh"
}

run_heki_backend_install_script() {
    clear
    if [ "$EUID" -ne 0 ]; then
        print_red "请使用 root 权限运行此功能。"
        pause
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        print_red "当前系统缺少 curl，无法运行 heki 安装脚本。"
        pause
        return
    fi

    run_remote_script "安装 heki 后端" "https://raw.githubusercontent.com/hekicore/heki/master/install.sh"
}

change_ssh_port() {
    clear
    local config="/etc/ssh/sshd_config"
    local backup
    local current_port
    local new_port
    local restart_ok=0

    print_cyan "修改 SSH 端口"

    if [ "$EUID" -ne 0 ]; then
        print_red "请使用 root 权限运行此功能。"
        pause
        return
    fi

    if [ ! -f "$config" ]; then
        print_red "未找到 SSH 配置文件：$config"
        pause
        return
    fi

    current_port="$(grep -Ei '^[[:space:]]*Port[[:space:]]+[0-9]+' "$config" | tail -n 1 | sed -E 's/^[[:space:]]*Port[[:space:]]+//')"
    current_port="${current_port:-22}"
    printf "当前 SSH 端口: %s\n" "$current_port"
    printf "请输入新的 SSH 端口: "
    read -r new_port

    case "$new_port" in
        ''|*[!0-9]*)
            print_red "端口必须是 1-65535 之间的数字。"
            pause
            return
            ;;
    esac

    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        print_red "端口必须是 1-65535 之间的数字。"
        pause
        return
    fi

    if [ "$new_port" != "$current_port" ]; then
        if command -v ss >/dev/null 2>&1; then
            if ss -tln 2>/dev/null | awk '{print $4}' | grep -E ":$new_port\$" >/dev/null 2>&1; then
                print_yellow "注意：该端口已被其他服务占用。"
                confirm "仍然继续？" || { pause; return; }
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tln 2>/dev/null | awk '{print $4}' | grep -E ":$new_port\$" >/dev/null 2>&1; then
                print_yellow "注意：该端口已被其他服务占用。"
                confirm "仍然继续？" || { pause; return; }
            fi
        fi
    fi

    print_yellow "请确认防火墙和安全组已放行新端口，否则可能无法重新连接 SSH。"
    confirm "确认修改 SSH 端口？" || return

    backup="${config}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config" "$backup" || {
        print_red "备份 SSH 配置失败。"
        pause
        return
    }

    sed -i -E '/^[[:space:]]*#?[[:space:]]*Port[[:space:]]+/d' "$config"
    printf "\nPort %s\n" "$new_port" >> "$config"

    if command -v sshd >/dev/null 2>&1 && ! sshd -t; then
        cp "$backup" "$config"
        print_red "SSH 配置检查失败，已恢复备份：$backup"
        pause
        return
    fi

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
            restart_ok=1
        fi
    else
        if service sshd restart 2>/dev/null || service ssh restart 2>/dev/null; then
            restart_ok=1
        fi
    fi

    if [ "$restart_ok" -eq 1 ]; then
        print_green "SSH 端口已修改并已重启服务。配置备份：$backup"
    else
        print_yellow "SSH 配置已修改，但服务重启失败，请手动重启 ssh/sshd。配置备份：$backup"
    fi
    print_yellow "请使用新端口重新连接并确认可用后，再关闭当前 SSH 会话。"
    pause
}

run_install_htop() {
    clear
    print_cyan "安装 htop"

    if [ "$EUID" -ne 0 ]; then
        print_red "请使用 root 权限运行此功能。"
        pause
        return
    fi

    if command -v htop >/dev/null 2>&1; then
        print_green "htop 已安装。"
        htop --version
        pause
        return
    fi

    local pm=""
    if command -v apt-get >/dev/null 2>&1; then
        pm="apt"
    elif command -v dnf >/dev/null 2>&1; then
        pm="dnf"
    elif command -v yum >/dev/null 2>&1; then
        pm="yum"
    elif command -v pacman >/dev/null 2>&1; then
        pm="pacman"
    elif command -v zypper >/dev/null 2>&1; then
        pm="zypper"
    fi

    if [ -z "$pm" ]; then
        print_red "未检测到受支持的包管理器（apt/dnf/yum/pacman/zypper）。"
        pause
        return
    fi

    print_yellow "将使用 $pm 安装 htop..."
    confirm "确认继续？" || return

    case "$pm" in
        apt)
            if ! apt-get update -qq; then
                print_red "软件源更新失败，无法安装 htop。"
                pause
                return
            fi
            apt-get install -y -qq htop
            ;;
        dnf)    dnf install -y -q htop ;;
        yum)    yum install -y -q htop ;;
        pacman) pacman -Sy --noconfirm --needed htop ;;
        zypper) zypper --non-interactive install htop ;;
    esac

    if command -v htop >/dev/null 2>&1; then
        print_green "htop 安装成功。"
        htop --version
    else
        print_red "htop 安装失败，请手动检查。"
    fi

    pause
}

run_warp_go_script() {
    clear
    local tmp_dir
    local url="https://gitlab.com/fscarmen/warp/-/raw/main/warp-go.sh"
    print_cyan "安装 warp-go"

    if ! command -v wget >/dev/null 2>&1; then
        print_red "当前系统缺少 wget，无法运行 warp-go 脚本。"
        pause
        return
    fi

    print_yellow "远程脚本可能会修改系统网络配置，请确认来源可信后继续。"
    confirm "确认继续？" || return

    tmp_dir="$(mktemp -d)" || { print_red "创建临时目录失败。"; pause; return; }
    if ! wget -qN "$url" -P "$tmp_dir"; then
        print_red "warp-go 脚本下载失败。"
        rm -rf "$tmp_dir"
        pause
        return
    fi

    bash "$tmp_dir/warp-go.sh"
    local rc=$?
    rm -rf "$tmp_dir"
    if [ "$rc" -ne 0 ]; then
        print_red "远程脚本执行失败，请检查上方输出。"
    fi
    pause
}

show_menu() {
    clear
    print_blue "========================================"
    print_blue "  Linux Toolbox"
    print_blue "========================================"
    printf "\n"
    printf "1. 启用 BBR 加速\n"
    printf "2. 换源\n"
    printf "3. 修改 SSH 端口\n"
    printf "4. 安装 heki 后端\n"
    printf "5. 安装 htop\n"
    printf "6. 安装 warp-go\n"
    printf "0. 退出\n"
    printf "\n请输入选项: "
}

main() {
    while true; do
        show_menu
        read -r choice
        case "$choice" in
            1) run_bbr_acceleration_script ;;
            2) run_change_mirror_script ;;
            3) change_ssh_port ;;
            4) run_heki_backend_install_script ;;
            5) run_install_htop ;;
            6) run_warp_go_script ;;
            0) exit 0 ;;
            *) print_red "无效选择"; pause ;;
        esac
    done
}

main "$@"
