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

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_red "$(t '此功能需要 root 权限，请使用 root 用户或 sudo 运行。' 'This function requires root privileges. Please run as root or with sudo.')"
        return 1
    fi
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

detect_os() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        printf "%s" "${PRETTY_NAME:-$ID}"
    else
        uname -s
    fi
}

show_system_info() {
    clear
    print_cyan "$(t '系统信息' 'System Information')"
    printf "%s: %s\n" "$(t '系统' 'OS')" "$(detect_os)"
    printf "%s: %s\n" "$(t '内核' 'Kernel')" "$(uname -r)"
    printf "%s: %s\n" "$(t '架构' 'Arch')" "$(uname -m)"
    printf "%s: %s\n" "$(t '主机名' 'Hostname')" "$(hostname)"
    printf "%s: %s\n" "$(t '运行时间' 'Uptime')" "$(uptime -p 2>/dev/null || uptime)"
    pause
}

show_resource_usage() {
    clear
    print_cyan "$(t '资源使用情况' 'Resource Usage')"
    printf "\n%s\n" "$(t '内存：' 'Memory:')"
    free -h 2>/dev/null || print_yellow "$(t '当前系统缺少 free 命令。' 'The free command is unavailable on this system.')"
    printf "\n%s\n" "$(t '磁盘：' 'Disk:')"
    df -h 2>/dev/null || print_yellow "$(t '当前系统缺少 df 命令。' 'The df command is unavailable on this system.')"
    pause
}

show_bbr_status() {
    clear
    print_cyan "$(t 'BBR 状态' 'BBR Status')"
    printf "%s: %s\n" "$(t '队列算法' 'Queue discipline')" "$(sysctl -n net.core.default_qdisc 2>/dev/null || t '未知' 'Unknown')"
    printf "%s: %s\n" "$(t '拥塞控制' 'Congestion control')" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || t '未知' 'Unknown')"

    if lsmod 2>/dev/null | grep -q '^tcp_bbr'; then
        print_green "$(t 'tcp_bbr 模块已加载。' 'tcp_bbr module is loaded.')"
    else
        print_yellow "$(t '未检测到 tcp_bbr 模块，可能需要执行优化或重启。' 'tcp_bbr module was not detected. You may need to apply optimization or reboot.')"
    fi
    pause
}

show_port_usage() {
    clear
    print_cyan "$(t '端口占用' 'Port Usage')"
    printf "%s" "$(t '请输入端口号，留空显示全部监听端口' 'Enter a port, or leave empty to show all listening ports'): "
    read -r port

    if command -v ss >/dev/null 2>&1; then
        if [ -n "$port" ]; then
            ss -lntup 2>/dev/null | grep -E ":${port}[[:space:]]"
        else
            ss -lntup 2>/dev/null
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if [ -n "$port" ]; then
            netstat -lntup 2>/dev/null | grep -E ":${port}[[:space:]]"
        else
            netstat -lntup 2>/dev/null
        fi
    else
        print_red "$(t '当前系统缺少 ss/netstat 命令。' 'The ss/netstat command is unavailable on this system.')"
    fi
    pause
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
        bash <(curl -sL "$script_url")
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$script_url" | bash
    else
        print_red "$(t '当前系统缺少 curl/wget，无法下载远程脚本。' 'curl/wget is unavailable, cannot download the remote script.')"
    fi

    pause
}

run_bbr_acceleration_script() {
    run_remote_script \
        "$(t 'BBR 加速脚本' 'BBR Acceleration Script')" \
        "https://scripts.zeroteam.top/NATPlugin/tcp_zhcn.sh" \
        "https://scripts.zeroteam.top/NATPlugin/tcp.sh"
}

show_script_collection() {
    while true; do
        clear
        print_blue "========================================"
        print_blue "  $(t '脚本集合' 'Script Collection')"
        print_blue "========================================"
        printf "1. %s\n" "$(t 'BBR 加速脚本' 'BBR acceleration script')"
        printf "0. %s\n" "$(t '返回主菜单' 'Back to main menu')"
        printf "\n%s" "$(t '请输入选项' 'Enter option'): "
        read -r choice

        case "$choice" in
            1) run_bbr_acceleration_script ;;
            0) return ;;
            *) print_red "$(t '无效选择' 'Invalid choice')"; pause ;;
        esac
    done
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
    printf "1. %s\n" "$(t '系统信息' 'System information')"
    printf "2. %s\n" "$(t '资源使用情况' 'Resource usage')"
    printf "3. %s\n" "$(t '端口占用查看' 'Port usage')"
    printf "4. %s\n" "$(t 'BBR 状态查看' 'BBR status')"
    printf "5. %s\n" "$(t '脚本集合' 'Script collection')"
    printf "9. %s\n" "$(t '切换语言' 'Switch language')"
    printf "0. %s\n" "$(t '退出' 'Exit')"
    printf "\n%s" "$(t '请输入选项' 'Enter option'): "
}

main() {
    while true; do
        show_menu
        read -r choice
        case "$choice" in
            1) show_system_info ;;
            2) show_resource_usage ;;
            3) show_port_usage ;;
            4) show_bbr_status ;;
            5) show_script_collection ;;
            9) switch_language ;;
            0) exit 0 ;;
            *) print_red "$(t '无效选择' 'Invalid choice')"; pause ;;
        esac
    done
}

main "$@"
