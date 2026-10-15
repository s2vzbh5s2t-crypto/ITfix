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

# ==================== CDN 边缘 IP 钉定 ====================
# 把 CDN_PIN_DOMAIN 钉定到低延迟的 CDN 边缘 IP（默认香港）。
#
# 原理：VPS 的 GeoIP 归属地未及时更新时，Google 会按错误的地区给它分配远端
# 边缘节点。本功能携带 EDNS Client Subnet（+subnet）向权威 DNS 伪造目标地区
# 来源，获取该地区的边缘 IP 候选，用 ping 测速择优，写入 /etc/hosts 标记块
# 覆盖系统解析。依赖：dig（apt: dnsutils / yum、dnf: bind-utils）、ping。
# 逻辑回归测试: bash test-cdn-pin-logic.sh

CDN_PIN_DOMAIN="www.gstatic.com"
CDN_PIN_ECS_PREFIX="43.129.0.0/24"   # 香港 ECS 前缀（腾讯云 HK 段），可在 bgp.tools 换其它地区段
CDN_PIN_MAX_CANDIDATES=8              # 参与测速的候选 IP 上限
CDN_PIN_PING_COUNT=3                  # 每个候选 ping 次数
CDN_PIN_PING_WAIT=2                   # 单包超时（秒）
CDN_PIN_HOSTS="${CDN_PIN_HOSTS:-/etc/hosts}"  # 可用环境变量覆盖（测试用）
CDN_PIN_MARK_BEGIN="# BEGIN cdn-pin"
CDN_PIN_MARK_END="# END cdn-pin"

cdn_pin_die() {
    print_red "$1"
    exit 1
}

cdn_pin_require_root() {
    [ "$EUID" -eq 0 ] || cdn_pin_die "请使用 root 权限运行此功能（需要写入 ${CDN_PIN_HOSTS}）。"
}

cdn_pin_require_tools() {
    local t
    for t in dig ping awk grep; do
        command -v "$t" >/dev/null 2>&1 || cdn_pin_die "缺少依赖命令：$t（apt: dnsutils / yum: bind-utils）"
    done
}

# 发现候选 IP：系统解析 + 权威 NS 携带 ECS 的地区化解析
cdn_pin_discover_candidates() {
    local out ns
    out="$(dig +short +time=3 +tries=1 A "$CDN_PIN_DOMAIN" 2>/dev/null)"
    for ns in $(dig +short +time=3 +tries=1 NS "${CDN_PIN_DOMAIN#*.}" 2>/dev/null | head -n 2); do
        out="${out}
$(dig +short +time=3 +tries=1 A "$CDN_PIN_DOMAIN" "@${ns}" "+subnet=${CDN_PIN_ECS_PREFIX}" 2>/dev/null)"
    done
    printf '%s\n' "$out" \
        | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
        | awk '!seen[$0]++' \
        | head -n "$CDN_PIN_MAX_CANDIDATES"
}

# ping 一个 IP，输出平均延迟(ms)；不通输出空
cdn_pin_ping_avg() {
    local ip="$1" out
    out="$(ping -n -c "$CDN_PIN_PING_COUNT" -W "$CDN_PIN_PING_WAIT" "$ip" 2>/dev/null)"
    printf '%s\n' "$out" | grep -oE '[0-9.]+/[0-9.]+/[0-9.]+' | head -n 1 | cut -d/ -f2
}

# 对所有候选测速，输出 "ip avg_ms"（不通为 "ip -"）
cdn_pin_measure_candidates() {
    local ip avg
    for ip in "$@"; do
        avg="$(cdn_pin_ping_avg "$ip")"
        printf '%s %s\n' "$ip" "${avg:--}"
    done
}

# 从测速结果里选延迟最低的，输出 "ip avg_ms"；全部不通则无输出
cdn_pin_pick_best() {
    awk '$2 != "-" { if (min == "" || $2 + 0 < min) { min = $2 + 0; ip = $1; avg = $2 } }
         END { if (ip != "") print ip, avg }'
}

# 读取 hosts 中本功能写入的钉定 IP
cdn_pin_current() {
    awk -v b="$CDN_PIN_MARK_BEGIN" -v e="$CDN_PIN_MARK_END" -v d="$CDN_PIN_DOMAIN" '
        $0 == b { skip = 1; next }
        skip && $0 == e { skip = 0; next }
        skip && $2 == d { print $1; exit }' "$CDN_PIN_HOSTS" 2>/dev/null
}

# 删除标记块（保留其它所有内容）
cdn_pin_strip_block() {
    awk -v b="$CDN_PIN_MARK_BEGIN" -v e="$CDN_PIN_MARK_END" '
        $0 == b { skip = 1; next }
        skip && $0 == e { skip = 0; next }
        skip { next }
        { print }' "$1"
}

cdn_pin_build_block() {
    printf '%s\n' "$CDN_PIN_MARK_BEGIN"
    printf '# 由 cdn-pin 生成：%s（ECS %s），请勿手动编辑\n' "$CDN_PIN_DOMAIN" "$CDN_PIN_ECS_PREFIX"
    printf '%-15s %s\n' "$1" "$CDN_PIN_DOMAIN"
    printf '%s\n' "$CDN_PIN_MARK_END"
}

cdn_pin_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    exec 9>"${CDN_PIN_HOSTS}.cdn-pin.lock" 2>/dev/null || return 0
    flock -n 9 || cdn_pin_die "另一个 cdn-pin 实例正在运行。"
}

# 原子替换：strip 旧标记块（并去掉尾部空行）-> 追加新块 -> 同目录 mv
cdn_pin_write_block() {
    local block="$1" tmp owner
    tmp="$(mktemp "${CDN_PIN_HOSTS}.cdn-pin.XXXXXX")" || cdn_pin_die "创建临时文件失败。"
    if ! cdn_pin_strip_block "$CDN_PIN_HOSTS" | awk '
            { lines[NR] = $0 }
            END {
                n = NR
                while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
                for (i = 1; i <= n; i++) print lines[i]
            }' >"$tmp"; then
        rm -f "$tmp"
        cdn_pin_die "读取 ${CDN_PIN_HOSTS} 失败。"
    fi
    printf '\n%s\n' "$block" >>"$tmp"
    owner="$(stat -c '%u:%g' "$CDN_PIN_HOSTS" 2>/dev/null || printf '0:0')"
    chown "$owner" "$tmp" 2>/dev/null || true
    chmod 0644 "$tmp"
    if ! mv -f "$tmp" "$CDN_PIN_HOSTS"; then
        rm -f "$tmp"
        cdn_pin_die "写入 ${CDN_PIN_HOSTS} 失败。"
    fi
}

cdn_pin_flush_caches() {
    command -v resolvectl >/dev/null 2>&1 && resolvectl flush-caches >/dev/null 2>&1 && return 0
    command -v systemd-resolve >/dev/null 2>&1 && systemd-resolve --flush-caches >/dev/null 2>&1 && return 0
    command -v nscd >/dev/null 2>&1 && nscd -i hosts >/dev/null 2>&1 && return 0
    return 0
}

# 发现 + 测速，结果存入全局 CDN_PIN_MEASURED（"ip avg" 行）
cdn_pin_discover() {
    local candidates
    print_cyan "发现候选 IP（权威 NS + ECS ${CDN_PIN_ECS_PREFIX}）..."
    candidates="$(cdn_pin_discover_candidates)"
    [ -n "$candidates" ] || return 1
    # shellcheck disable=SC2086
    CDN_PIN_MEASURED="$(cdn_pin_measure_candidates $candidates)"
    [ -n "$CDN_PIN_MEASURED" ] || return 1
    return 0
}

cdn_pin_print_measured() {
    printf "\n%-16s %s\n" "候选 IP" "ping 平均延迟(ms)"
    printf "%s\n" "------------------------------------------------"
    printf '%s\n' "$CDN_PIN_MEASURED" | awk '{ printf "%-16s %s\n", $1, ($2 == "-" ? "不通" : $2) }'
    printf "\n"
}

# 输出择优结果（全局 CDN_PIN_BEST）；全不通且 CDN_PIN_FORCE=1 时取第一个，否则中止
cdn_pin_select_best() {
    CDN_PIN_BEST="$(printf '%s\n' "$CDN_PIN_MEASURED" | cdn_pin_pick_best)"
    if [ -z "$CDN_PIN_BEST" ]; then
        if [ "${CDN_PIN_FORCE:-0}" = "1" ]; then
            CDN_PIN_BEST="$(printf '%s\n' "$CDN_PIN_MEASURED" | head -n 1)"
            print_yellow "全部 ping 不通，按 CDN_PIN_FORCE=1 强制采用: $CDN_PIN_BEST"
        else
            cdn_pin_die "所有候选都 ping 不通，${CDN_PIN_HOSTS} 未改动。（禁 ICMP 的 VPS 可用 CDN_PIN_FORCE=1）"
        fi
    fi
    print_green "择优结果: $CDN_PIN_BEST"
}

cdn_pin_preview() {
    cdn_pin_require_tools
    print_blue "======== 预览（不写入 ${CDN_PIN_HOSTS}）========"
    cdn_pin_discover || cdn_pin_die "未发现任何候选 IP。"
    cdn_pin_print_measured
    cdn_pin_select_best
}

cdn_pin_apply() {
    local new_pin
    cdn_pin_require_root
    cdn_pin_require_tools
    cdn_pin_lock
    print_blue "======== 应用钉定 ${CDN_PIN_DOMAIN} ========"

    cdn_pin_discover || cdn_pin_die "未发现任何候选 IP，已放弃，${CDN_PIN_HOSTS} 未改动。"
    cdn_pin_print_measured
    cdn_pin_select_best
    new_pin="${CDN_PIN_BEST%% *}"

    if [ "$(cdn_pin_current)" = "$new_pin" ]; then
        print_green "钉定 IP 无变化（${new_pin}），跳过写入。"
        cdn_pin_flush_caches
        return 0
    fi

    cp -a "$CDN_PIN_HOSTS" "$CDN_PIN_HOSTS.cdn-pin.bak" || cdn_pin_die "备份 ${CDN_PIN_HOSTS} 失败。"
    cdn_pin_write_block "$(cdn_pin_build_block "$new_pin")"

    if [ "$(cdn_pin_current)" = "$new_pin" ]; then
        cdn_pin_flush_caches
        print_green "已写入 ${CDN_PIN_HOSTS}：${CDN_PIN_DOMAIN} -> ${new_pin}（备份: ${CDN_PIN_HOSTS}.cdn-pin.bak）"
        command -v getent >/dev/null 2>&1 \
            && printf "getent 解析结果: %s\n" "$(getent hosts "$CDN_PIN_DOMAIN" | head -n 1 | awk '{print $1}')"
    else
        cp -a "$CDN_PIN_HOSTS.cdn-pin.bak" "$CDN_PIN_HOSTS"
        cdn_pin_die "回读校验失败，已恢复备份。"
    fi
}

cdn_pin_status() {
    local pinned sys_ip
    cdn_pin_require_tools
    print_blue "======== 状态 ========"

    pinned="$(cdn_pin_current)"
    if [ -n "$pinned" ]; then
        printf "当前钉定: %-16s ping %s ms\n" "$pinned" "$(cdn_pin_ping_avg "$pinned" | { grep . || printf '不通'; })"
    else
        print_yellow "当前未钉定（${CDN_PIN_HOSTS} 中无 cdn-pin 标记块）。"
    fi

    sys_ip="$(dig +short +time=3 +tries=1 A "$CDN_PIN_DOMAIN" 2>/dev/null | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -n 1)"
    if [ -n "$sys_ip" ]; then
        printf "系统解析: %-16s ping %s ms\n" "$sys_ip" "$(cdn_pin_ping_avg "$sys_ip" | { grep . || printf '不通'; })"
    else
        print_yellow "系统解析失败（DNS 查询无结果）。"
    fi

    command -v getent >/dev/null 2>&1 \
        && printf "系统生效: %s\n" "$(getent hosts "$CDN_PIN_DOMAIN" | head -n 1 | awk '{print $1}')"
    printf "ECS 前缀: %s\n" "$CDN_PIN_ECS_PREFIX"
}

cdn_pin_rollback() {
    cdn_pin_require_root
    cdn_pin_lock
    print_blue "======== 回滚 ========"

    grep -qF "$CDN_PIN_MARK_BEGIN" "$CDN_PIN_HOSTS" 2>/dev/null \
        || { print_yellow "未找到钉定条目，无需回滚。"; return 0; }

    cp -a "$CDN_PIN_HOSTS" "$CDN_PIN_HOSTS.cdn-pin.bak" || cdn_pin_die "备份 ${CDN_PIN_HOSTS} 失败。"
    cdn_pin_write_block ""
    cdn_pin_flush_caches
    print_green "已移除钉定条目，恢复系统解析。（备份: ${CDN_PIN_HOSTS}.cdn-pin.bak）"
}

run_cdn_pin_menu() {
    local choice
    while true; do
        clear
        print_blue "========================================"
        print_blue "  CDN 边缘 IP 钉定（${CDN_PIN_DOMAIN}）"
        print_blue "========================================"
        printf "\n"
        printf "当前钉定: %s\n\n" "$(cdn_pin_current 2>/dev/null || true)"
        printf "1. 预览（发现候选 + ping 测速，不写入）\n"
        printf "2. 应用（写入 %s）\n" "$CDN_PIN_HOSTS"
        printf "3. 查看状态\n"
        printf "4. 回滚（移除钉定）\n"
        printf "0. 返回\n"
        printf "\n请输入选项: "
        read -r choice
        # 在子 shell 中执行，内部 die 的 exit 不会退出整个工具箱
        case "$choice" in
            1) printf "\n"; ( cdn_pin_preview ); pause ;;
            2) printf "\n"; ( cdn_pin_apply ); pause ;;
            3) printf "\n"; ( cdn_pin_status ); pause ;;
            4) printf "\n"; ( cdn_pin_rollback ); pause ;;
            0) return ;;
            *) print_red "无效选择"; pause ;;
        esac
    done
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
    printf "7. CDN 边缘 IP 钉定（gstatic）\n"
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
            7) run_cdn_pin_menu ;;
            0) exit 0 ;;
            *) print_red "无效选择"; pause ;;
        esac
    done
}

main "$@"
