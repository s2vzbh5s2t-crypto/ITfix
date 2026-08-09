#!/usr/bin/env bash

set -o pipefail

LANGUAGE="${LANGUAGE:-zh}"

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

t() {
    local zh="$1"
    local en="$2"

    if [ "$LANGUAGE" = "en" ]; then
        printf "%s" "$en"
    else
        printf "%s" "$zh"
    fi
}

pause() {
    printf "\n%s" "$(t '按回车键继续...' 'Press Enter to continue...')"
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
    local zh_url="$2"
    local en_url="$3"
    local script_url

    print_cyan "$title"

    if [ "$LANGUAGE" = "en" ]; then
        script_url="$en_url"
    else
        script_url="$zh_url"
    fi

    printf "%s: %s\n" "$(t '即将运行远程脚本' 'Remote script')" "$script_url"
    print_yellow "$(t '远程脚本可能会修改系统网络配置，请确认来源可信后继续。' 'The remote script may change system network settings. Continue only if you trust the source.')"
    confirm "$(t '确认继续？' 'Continue?')" || return

    local tmp_script=""
    if command -v curl >/dev/null 2>&1; then
        tmp_script="$(mktemp)" || { print_red "$(t '创建临时文件失败。' 'Failed to create a temp file.')"; pause; return; }
        if ! curl -fsSL "$script_url" -o "$tmp_script"; then
            print_red "$(t '远程脚本下载失败：' 'Failed to download the remote script:') $script_url"
            rm -f "$tmp_script"
            pause
            return
        fi
    elif command -v wget >/dev/null 2>&1; then
        tmp_script="$(mktemp)" || { print_red "$(t '创建临时文件失败。' 'Failed to create a temp file.')"; pause; return; }
        if ! wget -qO "$tmp_script" "$script_url"; then
            print_red "$(t '远程脚本下载失败：' 'Failed to download the remote script:') $script_url"
            rm -f "$tmp_script"
            pause
            return
        fi
    else
        print_red "$(t '当前系统缺少 curl/wget，无法下载远程脚本。' 'curl/wget is unavailable, cannot download the remote script.')"
        pause
        return
    fi

    bash "$tmp_script"
    local rc=$?
    rm -f "$tmp_script"
    if [ "$rc" -ne 0 ]; then
        print_red "$(t '远程脚本执行失败，请检查上方输出。' 'The remote script failed. Check the output above.')"
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

    print_cyan "$(t '启用 BBR 加速' 'Enable BBR Acceleration')"

    if [ "$EUID" -ne 0 ]; then
        print_red "$(t '请使用 root 权限运行此功能。' 'Please run this feature as root.')"
        pause
        return
    fi

    if ! command -v sysctl >/dev/null 2>&1; then
        print_red "$(t '当前系统缺少 sysctl，无法配置 BBR。' 'sysctl is unavailable, cannot configure BBR.')"
        pause
        return
    fi

    current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    current_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    available_congestion="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    allowed_congestion="$(sysctl -n net.ipv4.tcp_allowed_congestion_control 2>/dev/null || true)"

    printf "%s: %s\n" "$(t '当前队列算法' 'Current queue discipline')" "${current_qdisc:-unknown}"
    printf "%s: %s\n" "$(t '当前拥塞控制' 'Current congestion control')" "${current_congestion:-unknown}"
    printf "%s: %s\n" "$(t '可用拥塞控制' 'Available congestion controls')" "${available_congestion:-unknown}"
    printf "%s: %s\n" "$(t '允许拥塞控制' 'Allowed congestion controls')" "${allowed_congestion:-unknown}"

    if [ -n "$current_congestion" ] && ! sysctl -w net.ipv4.tcp_congestion_control="$current_congestion" >/dev/null 2>&1; then
        print_red "$(t '当前环境无法修改网络相关 sysctl 参数（常见于 OpenVZ/LXC 或容器环境），无法启用 BBR。' 'This environment cannot modify network sysctl settings (common in OpenVZ/LXC or container environments). BBR cannot be enabled.')"
        pause
        return
    fi

    if ! printf '%s\n' "$available_congestion" | grep -qw bbr; then
        if command -v modprobe >/dev/null 2>&1; then
            modprobe tcp_bbr 2>/dev/null || true
            available_congestion="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
        fi

        if ! printf '%s\n' "$available_congestion" | grep -qw bbr; then
            print_red "$(t '当前内核未提供 BBR，可能需要升级内核或启用 tcp_bbr 模块。' 'The current kernel does not provide BBR. Upgrade the kernel or enable the tcp_bbr module.')"
            pause
            return
        fi
    fi

    if [ "$current_qdisc" != "fq" ]; then
        if [ ! -d /sys/module/sch_fq ]; then
            command -v modprobe >/dev/null 2>&1 && modprobe sch_fq 2>/dev/null || true
        fi

        if [ ! -d /sys/module/sch_fq ]; then
            print_yellow "$(t '当前内核缺少 fq 队列算法（可能需要加载 sch_fq 模块或升级内核）。' 'The current kernel lacks the fq qdisc (load the sch_fq module or upgrade the kernel).')"
            if confirm "$(t '是否仅启用 BBR，跳过 fq 队列设置？' 'Enable BBR only and skip the fq qdisc setting?')"; then
                use_fq=0
            else
                pause
                return
            fi
        fi
    fi

    if [ "$use_fq" -eq 1 ]; then
        print_yellow "$(t '将写入配置到 /etc/sysctl.d/bbr.conf：net.core.default_qdisc=fq，net.ipv4.tcp_congestion_control=bbr。' 'Will write to /etc/sysctl.d/bbr.conf: net.core.default_qdisc=fq, net.ipv4.tcp_congestion_control=bbr.')"
    else
        print_yellow "$(t '将写入配置到 /etc/sysctl.d/bbr.conf：net.ipv4.tcp_congestion_control=bbr（跳过 fq 队列设置）。' 'Will write to /etc/sysctl.d/bbr.conf: net.ipv4.tcp_congestion_control=bbr (skipping the fq qdisc setting).')"
    fi
    confirm "$(t '确认继续？' 'Continue?')" || return

    if ! mkdir -p "$(dirname "$config")"; then
        print_red "$(t '创建 sysctl 配置目录失败。' 'Failed to create sysctl config directory.')"
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
        print_red "$(t '写入 BBR 配置失败。' 'Failed to write BBR config.')"
        pause
        return
    fi

    if ! sysctl -p "$config"; then
        print_red "$(t '应用 BBR 配置失败，请检查系统是否支持相关参数。' 'Failed to apply BBR config. Check whether the system supports these parameters.')"
        pause
        return
    fi

    current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    current_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"

    printf "%s: %s\n" "$(t '当前队列算法' 'Current queue discipline')" "${current_qdisc:-unknown}"
    printf "%s: %s\n" "$(t '当前拥塞控制' 'Current congestion control')" "${current_congestion:-unknown}"

    if [ "$current_congestion" = "bbr" ] && { [ "$use_fq" -eq 0 ] || [ "$current_qdisc" = "fq" ]; }; then
        print_green "$(t 'BBR 已启用并写入持久配置：' 'BBR is enabled and persisted at:') $config"
    else
        print_yellow "$(t '配置已写入，但当前状态未完全匹配，可能需要重启或检查内核支持。' 'Config was written, but current state does not fully match. A reboot or kernel check may be required.')"
    fi

    pause
}

run_change_mirror_script() {
    run_remote_script \
        "$(t 'Linux 换源脚本' 'Linux Mirror Script')" \
        "https://linuxmirrors.cn/main.sh" \
        "https://linuxmirrors.cn/main.sh"
}

run_heki_backend_install_script() {
    clear
    if [ "$EUID" -ne 0 ]; then
        print_red "$(t '请使用 root 权限运行此功能。' 'Please run this feature as root.')"
        pause
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        print_red "$(t '当前系统缺少 curl，无法运行 heki 安装脚本。' 'curl is unavailable, cannot run the heki install script.')"
        pause
        return
    fi

    run_remote_script \
        "$(t '安装 heki 后端' 'Install heki backend')" \
        "https://raw.githubusercontent.com/hekicore/heki/master/install.sh" \
        "https://raw.githubusercontent.com/hekicore/heki/master/install.sh"
}

change_ssh_port() {
    clear
    local config="/etc/ssh/sshd_config"
    local backup
    local current_port
    local new_port
    local restart_ok=0

    print_cyan "$(t '修改 SSH 端口' 'Change SSH Port')"

    if [ "$EUID" -ne 0 ]; then
        print_red "$(t '请使用 root 权限运行此功能。' 'Please run this feature as root.')"
        pause
        return
    fi

    if [ ! -f "$config" ]; then
        print_red "$(t '未找到 SSH 配置文件：' 'SSH config file was not found:') $config"
        pause
        return
    fi

    current_port="$(grep -Ei '^[[:space:]]*Port[[:space:]]+[0-9]+' "$config" | tail -n 1 | sed -E 's/^[[:space:]]*Port[[:space:]]+//')"
    current_port="${current_port:-22}"
    printf "%s: %s\n" "$(t '当前 SSH 端口' 'Current SSH port')" "$current_port"
    printf "%s" "$(t '请输入新的 SSH 端口' 'Enter new SSH port'): "
    read -r new_port

    case "$new_port" in
        ''|*[!0-9]*)
            print_red "$(t '端口必须是 1-65535 之间的数字。' 'Port must be a number between 1 and 65535.')"
            pause
            return
            ;;
    esac

    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        print_red "$(t '端口必须是 1-65535 之间的数字。' 'Port must be a number between 1 and 65535.')"
        pause
        return
    fi

    if [ "$new_port" != "$current_port" ]; then
        if command -v ss >/dev/null 2>&1; then
            if ss -tln 2>/dev/null | awk '{print $4}' | grep -E ":$new_port\$" >/dev/null 2>&1; then
                print_yellow "$(t '注意：该端口已被其他服务占用。' 'Warning: this port is already in use by another service.')"
                confirm "$(t '仍然继续？' 'Continue anyway?')" || { pause; return; }
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tln 2>/dev/null | awk '{print $4}' | grep -E ":$new_port\$" >/dev/null 2>&1; then
                print_yellow "$(t '注意：该端口已被其他服务占用。' 'Warning: this port is already in use by another service.')"
                confirm "$(t '仍然继续？' 'Continue anyway?')" || { pause; return; }
            fi
        fi
    fi

    print_yellow "$(t '请确认防火墙和安全组已放行新端口，否则可能无法重新连接 SSH。' 'Make sure the firewall and security group allow the new port, or SSH may become unreachable.')"
    confirm "$(t '确认修改 SSH 端口？' 'Change SSH port?')" || return

    backup="${config}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config" "$backup" || {
        print_red "$(t '备份 SSH 配置失败。' 'Failed to back up SSH config.')"
        pause
        return
    }

    sed -i -E '/^[[:space:]]*#?[[:space:]]*Port[[:space:]]+/d' "$config"
    printf "\nPort %s\n" "$new_port" >> "$config"

    if command -v sshd >/dev/null 2>&1 && ! sshd -t; then
        cp "$backup" "$config"
        print_red "$(t 'SSH 配置检查失败，已恢复备份：' 'SSH config test failed, backup was restored:') $backup"
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
        print_green "$(t 'SSH 端口已修改并已重启服务。配置备份：' 'SSH port was changed and the service was restarted. Config backup:') $backup"
    else
        print_yellow "$(t 'SSH 配置已修改，但服务重启失败，请手动重启 ssh/sshd。配置备份：' 'SSH config was changed, but service restart failed. Restart ssh/sshd manually. Config backup:') $backup"
    fi
    print_yellow "$(t '请使用新端口重新连接并确认可用后，再关闭当前 SSH 会话。' 'Reconnect with the new port and verify it works before closing this SSH session.')"
    pause
}

run_install_htop() {
    clear
    print_cyan "$(t '安装 htop' 'Install htop')"

    if [ "$EUID" -ne 0 ]; then
        print_red "$(t '请使用 root 权限运行此功能。' 'Please run this feature as root.')"
        pause
        return
    fi

    if command -v htop >/dev/null 2>&1; then
        print_green "$(t 'htop 已安装。' 'htop is already installed.')"
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
        print_red "$(t '未检测到受支持的包管理器（apt/dnf/yum/pacman/zypper）。' 'No supported package manager found (apt/dnf/yum/pacman/zypper).')"
        pause
        return
    fi

    print_yellow "$(t '将使用' 'Will use') $pm $(t '安装 htop...' 'to install htop...')"
    confirm "$(t '确认继续？' 'Continue?')" || return

    case "$pm" in
        apt)
            if ! apt-get update -qq; then
                print_red "$(t '软件源更新失败，无法安装 htop。' 'Failed to update package lists, cannot install htop.')"
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
        print_green "$(t 'htop 安装成功。' 'htop installed successfully.')"
        htop --version
    else
        print_red "$(t 'htop 安装失败，请手动检查。' 'htop installation failed. Please check manually.')"
    fi

    pause
}

run_warp_go_script() {
    clear
    local tmp_dir
    local url="https://gitlab.com/fscarmen/warp/-/raw/main/warp-go.sh"
    print_cyan "$(t '安装 warp-go' 'Install warp-go')"

    if ! command -v wget >/dev/null 2>&1; then
        print_red "$(t '当前系统缺少 wget，无法运行 warp-go 脚本。' 'wget is unavailable, cannot run the warp-go script.')"
        pause
        return
    fi

    print_yellow "$(t '远程脚本可能会修改系统网络配置，请确认来源可信后继续。' 'The remote script may change system network settings. Continue only if you trust the source.')"
    confirm "$(t '确认继续？' 'Continue?')" || return

    tmp_dir="$(mktemp -d)" || { print_red "$(t '创建临时目录失败。' 'Failed to create a temp directory.')"; pause; return; }
    if ! wget -qN "$url" -P "$tmp_dir"; then
        print_red "$(t 'warp-go 脚本下载失败。' 'Failed to download the warp-go script.')"
        rm -rf "$tmp_dir"
        pause
        return
    fi

    bash "$tmp_dir/warp-go.sh"
    local rc=$?
    rm -rf "$tmp_dir"
    if [ "$rc" -ne 0 ]; then
        print_red "$(t '远程脚本执行失败，请检查上方输出。' 'The remote script failed. Check the output above.')"
    fi
    pause
}

switch_language() {
    clear
    print_cyan "Language / 语言"
    printf "1. 中文\n"
    printf "2. English\n"
    printf "\n%s" "$(t '请选择' 'Please choose'): "
    read -r choice

    case "$choice" in
        1) LANGUAGE="zh" ;;
        2) LANGUAGE="en" ;;
        *) print_red "$(t '无效选择' 'Invalid choice')"; pause; return ;;
    esac

    print_green "$(t '语言已切换为中文。' 'Language switched to English.')"
    pause
}

show_menu() {
    clear
    print_blue "========================================"
    print_blue "  Linux Toolbox"
    print_blue "========================================"
    printf "%s: %s\n\n" "$(t '当前语言' 'Current language')" "$LANGUAGE"
    printf "1. %s\n" "$(t '启用 BBR 加速' 'Enable BBR acceleration')"
    printf "2. %s\n" "$(t '换源' 'Change mirror')"
    printf "3. %s\n" "$(t '修改 SSH 端口' 'Change SSH port')"
    printf "4. %s\n" "$(t '安装 heki 后端' 'Install heki backend')"
    printf "5. %s\n" "$(t '安装 htop' 'Install htop')"
    printf "6. %s\n" "$(t '安装 warp-go' 'Install warp-go')"
    printf "7. %s\n" "$(t '中英文切换' 'Switch Chinese/English')"
    printf "0. %s\n" "$(t '退出' 'Exit')"
    printf "\n%s" "$(t '请输入选项' 'Enter option'): "
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
            7) switch_language ;;
            0) exit 0 ;;
            *) print_red "$(t '无效选择' 'Invalid choice')"; pause ;;
        esac
    done
}

main "$@"
