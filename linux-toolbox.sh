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
    run_remote_script \
        "$(t 'BBR 加速脚本' 'BBR Acceleration Script')" \
        "https://scripts.zeroteam.top/NATPlugin/tcp_zhcn.sh" \
        "https://scripts.zeroteam.top/NATPlugin/tcp.sh"
}

run_change_mirror_script() {
    run_remote_script \
        "$(t 'Linux 换源脚本' 'Linux Mirror Script')" \
        "https://linuxmirrors.cn/main.sh" \
        "https://linuxmirrors.cn/main.sh"
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
    printf "1. %s\n" "$(t '执行 BBR 加速' 'Run BBR acceleration')"
    printf "2. %s\n" "$(t '换源' 'Change mirror')"
    printf "3. %s\n" "$(t '中英文切换' 'Switch Chinese/English')"
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
            3) switch_language ;;
            0) exit 0 ;;
            *) print_red "$(t '无效选择' 'Invalid choice')"; pause ;;
        esac
    done
}

main "$@"
