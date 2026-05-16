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

    if command -v curl >/dev/null 2>&1; then
        bash <(curl -sSL "$script_url")
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$script_url" | bash
    else
        print_red "$(t '当前系统缺少 curl/wget，无法下载远程脚本。' 'curl/wget is unavailable, cannot download the remote script.')"
    fi

    pause
}

run_bbr_acceleration_script() {
    clear
    local config="/etc/sysctl.d/bbr.conf"
    local current_qdisc
    local current_congestion
    local available_congestion

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

    printf "%s: %s\n" "$(t '当前队列算法' 'Current queue discipline')" "${current_qdisc:-unknown}"
    printf "%s: %s\n" "$(t '当前拥塞控制' 'Current congestion control')" "${current_congestion:-unknown}"
    printf "%s: %s\n" "$(t '可用拥塞控制' 'Available congestion controls')" "${available_congestion:-unknown}"

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

    print_yellow "$(t '将写入最小化 BBR 配置到 /etc/sysctl.d/bbr.conf：net.core.default_qdisc=fq，net.ipv4.tcp_congestion_control=bbr。' 'The minimal BBR config will be written to /etc/sysctl.d/bbr.conf: net.core.default_qdisc=fq, net.ipv4.tcp_congestion_control=bbr.')"
    confirm "$(t '确认继续？' 'Continue?')" || return

    if ! mkdir -p "$(dirname "$config")"; then
        print_red "$(t '创建 sysctl 配置目录失败。' 'Failed to create sysctl config directory.')"
        pause
        return
    fi

    if ! cat >"$config" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    then
        print_red "$(t '写入 BBR 配置失败。' 'Failed to write BBR config.')"
        pause
        return
    fi

    if ! sysctl -p "$config" >/dev/null; then
        print_red "$(t '应用 BBR 配置失败，请检查系统是否支持相关参数。' 'Failed to apply BBR config. Check whether the system supports these parameters.')"
        pause
        return
    fi

    current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    current_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"

    printf "%s: %s\n" "$(t '当前队列算法' 'Current queue discipline')" "${current_qdisc:-unknown}"
    printf "%s: %s\n" "$(t '当前拥塞控制' 'Current congestion control')" "${current_congestion:-unknown}"

    if [ "$current_qdisc" = "fq" ] && [ "$current_congestion" = "bbr" ]; then
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

change_ssh_port() {
    clear
    local config="/etc/ssh/sshd_config"
    local backup
    local current_port
    local new_port
    local restart_ok=0

    print_cyan "$(t '修改 SSH 端口' 'Change SSH Port')"

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

    print_yellow "$(t '请确认防火墙和安全组已放行新端口，否则可能无法重新连接 SSH。' 'Make sure the firewall and security group allow the new port, or SSH may become unreachable.')"
    confirm "$(t '确认修改 SSH 端口？' 'Change SSH port?')" || return

    backup="${config}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config" "$backup" || {
        print_red "$(t '备份 SSH 配置失败。' 'Failed to back up SSH config.')"
        pause
        return
    }

    if grep -Eq '^[[:space:]]*#?[[:space:]]*Port[[:space:]]+' "$config"; then
        sed -i "0,/^[[:space:]]*#\?[[:space:]]*Port[[:space:]]\+/{s/^[[:space:]]*#\?[[:space:]]*Port[[:space:]]\+.*/Port $new_port/}" "$config"
    else
        printf "\nPort %s\n" "$new_port" >> "$config"
    fi

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
    printf "4. %s\n" "$(t '中英文切换' 'Switch Chinese/English')"
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
            4) switch_language ;;
            0) exit 0 ;;
            *) print_red "$(t '无效选择' 'Invalid choice')"; pause ;;
        esac
    done
}

main "$@"
