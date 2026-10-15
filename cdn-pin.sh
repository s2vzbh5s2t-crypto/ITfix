#!/usr/bin/env bash
#
# cdn-pin.sh — 把 www.gstatic.com 钉定到低延迟的 CDN 边缘 IP（默认香港）
#
# 原理：VPS 的 GeoIP 归属地未及时更新时，Google 会按错误的地区分配远端边缘节点。
# 本脚本携带 EDNS Client Subnet（+subnet）向权威 DNS 伪造目标地区来源，获取该地区
# 的边缘 IP 候选，用 ping 测速择优，写入 /etc/hosts 标记块覆盖系统解析。
#
# 用法：
#   ./cdn-pin.sh preview    发现候选 + ping 测速（不写入）
#   ./cdn-pin.sh apply      发现 + 测速 + 写入 /etc/hosts（需 root）
#   ./cdn-pin.sh status     查看当前钉定与系统解析对比
#   ./cdn-pin.sh rollback   移除本工具写入的钉定条目（需 root）
#
# 依赖：dig（apt: dnsutils / yum、dnf: bind-utils）、ping
# 环境变量：
#   CDN_PIN_HOSTS=/path/to/hosts   指定 hosts 文件（测试用）
#   CDN_PIN_FORCE=1                全部候选 ping 不通时（禁 ICMP）跳过测速强制写入

set -o pipefail

# ---------------- 配置 ----------------
DOMAIN="www.gstatic.com"
ECS_PREFIX="43.129.0.0/24"   # 香港 ECS 查询前缀（腾讯云 HK 段），可在 bgp.tools 换其它地区段
MAX_CANDIDATES=8              # 参与测速的候选 IP 上限
PING_COUNT=3                  # 每个候选 ping 次数
PING_WAIT=2                   # 单包超时（秒）
HOSTS_FILE="${CDN_PIN_HOSTS:-/etc/hosts}"
MARK_BEGIN="# BEGIN cdn-pin"
MARK_END="# END cdn-pin"
# --------------------------------------

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

ZONE="${DOMAIN#*.}"   # www.gstatic.com -> gstatic.com

die() {
    print_red "$1"
    exit 1
}

require_root() {
    [ "$EUID" -eq 0 ] || die "请使用 root 权限运行此功能（需要写入 ${HOSTS_FILE}）。"
}

require_tools() {
    local t
    for t in dig ping awk grep; do
        command -v "$t" >/dev/null 2>&1 || die "缺少依赖命令：$t（apt: dnsutils / yum: bind-utils）"
    done
}

# 发现候选 IP：系统解析 + 权威 NS 携带 ECS 的地区化解析
discover_candidates() {
    local out ns
    out="$(dig +short +time=3 +tries=1 A "$DOMAIN" 2>/dev/null)"
    for ns in $(dig +short +time=3 +tries=1 NS "$ZONE" 2>/dev/null | head -n 2); do
        out="${out}
$(dig +short +time=3 +tries=1 A "$DOMAIN" "@${ns}" "+subnet=${ECS_PREFIX}" 2>/dev/null)"
    done
    printf '%s\n' "$out" \
        | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
        | awk '!seen[$0]++' \
        | head -n "$MAX_CANDIDATES"
}

# ping 一个 IP，输出平均延迟(ms)；不通输出空
ping_avg() {
    local ip="$1" out
    out="$(ping -n -c "$PING_COUNT" -W "$PING_WAIT" "$ip" 2>/dev/null)"
    printf '%s\n' "$out" | grep -oE '[0-9.]+/[0-9.]+/[0-9.]+' | head -n 1 | cut -d/ -f2
}

# 对所有候选测速，输出 "ip avg_ms"（不通为 "ip -"）
measure_candidates() {
    local ip avg
    for ip in "$@"; do
        avg="$(ping_avg "$ip")"
        printf '%s %s\n' "$ip" "${avg:--}"
    done
}

# 从测速结果里选延迟最低的，输出 "ip avg_ms"；全部不通则无输出
pick_best() {
    awk '$2 != "-" { if (min == "" || $2 + 0 < min) { min = $2 + 0; ip = $1; avg = $2 } }
         END { if (ip != "") print ip, avg }'
}

# 读取 hosts 中本工具写入的钉定 IP
current_pin() {
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" -v d="$DOMAIN" '
        $0 == b { skip = 1; next }
        skip && $0 == e { skip = 0; next }
        skip && $2 == d { print $1; exit }' "$HOSTS_FILE" 2>/dev/null
}

# 删除标记块（保留其它所有内容）
strip_block() {
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
        $0 == b { skip = 1; next }
        skip && $0 == e { skip = 0; next }
        skip { next }
        { print }' "$1"
}

build_block() {
    printf '%s\n' "$MARK_BEGIN"
    printf '# 由 cdn-pin.sh 生成：%s（ECS %s），请勿手动编辑\n' "$DOMAIN" "$ECS_PREFIX"
    printf '%-15s %s\n' "$1" "$DOMAIN"
    printf '%s\n' "$MARK_END"
}

acquire_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    exec 9>"${HOSTS_FILE}.cdn-pin.lock" 2>/dev/null || return 0
    flock -n 9 || die "另一个 cdn-pin 实例正在运行。"
}

# 原子替换：strip 旧标记块（并去掉尾部空行）-> 追加新块 -> 同目录 mv
write_hosts_with_block() {
    local block="$1" tmp owner
    tmp="$(mktemp "${HOSTS_FILE}.cdn-pin.XXXXXX")" || die "创建临时文件失败。"
    if ! strip_block "$HOSTS_FILE" | awk '
            { lines[NR] = $0 }
            END {
                n = NR
                while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
                for (i = 1; i <= n; i++) print lines[i]
            }' >"$tmp"; then
        rm -f "$tmp"
        die "读取 ${HOSTS_FILE} 失败。"
    fi
    printf '\n%s\n' "$block" >>"$tmp"
    owner="$(stat -c '%u:%g' "$HOSTS_FILE" 2>/dev/null || printf '0:0')"
    chown "$owner" "$tmp" 2>/dev/null || true
    chmod 0644 "$tmp"
    if ! mv -f "$tmp" "$HOSTS_FILE"; then
        rm -f "$tmp"
        die "写入 ${HOSTS_FILE} 失败。"
    fi
}

flush_caches() {
    command -v resolvectl >/dev/null 2>&1 && resolvectl flush-caches >/dev/null 2>&1 && return 0
    command -v systemd-resolve >/dev/null 2>&1 && systemd-resolve --flush-caches >/dev/null 2>&1 && return 0
    command -v nscd >/dev/null 2>&1 && nscd -i hosts >/dev/null 2>&1 && return 0
    return 0
}

# 发现 + 测速，结果存入全局 MEASURED（"ip avg" 行）
run_discovery() {
    local candidates
    print_cyan "发现候选 IP（权威 NS + ECS ${ECS_PREFIX}）..."
    candidates="$(discover_candidates)"
    [ -n "$candidates" ] || return 1
    # shellcheck disable=SC2086
    MEASURED="$(measure_candidates $candidates)"
    [ -n "$MEASURED" ] || return 1
    return 0
}

print_measured() {
    printf "\n%-16s %s\n" "候选 IP" "ping 平均延迟(ms)"
    printf "%s\n" "------------------------------------------------"
    printf '%s\n' "$MEASURED" | awk '{ printf "%-16s %s\n", $1, ($2 == "-" ? "不通" : $2) }'
    printf "\n"
}

# 输出择优结果（全局 BEST）；全不通且 CDN_PIN_FORCE=1 时取第一个，否则失败
select_best() {
    BEST="$(printf '%s\n' "$MEASURED" | pick_best)"
    if [ -z "$BEST" ]; then
        if [ "${CDN_PIN_FORCE:-0}" = "1" ]; then
            BEST="$(printf '%s\n' "$MEASURED" | head -n 1)"
            print_yellow "全部 ping 不通，按 CDN_PIN_FORCE=1 强制采用: $BEST"
        else
            die "所有候选都 ping 不通，${HOSTS_FILE} 未改动。（禁 ICMP 的 VPS 可用 CDN_PIN_FORCE=1）"
        fi
    fi
    print_green "择优结果: $BEST"
}

cmd_preview() {
    require_tools
    print_blue "======== 预览（不写入 ${HOSTS_FILE}）========"
    run_discovery || die "未发现任何候选 IP。"
    print_measured
    select_best
}

cmd_apply() {
    local new_pin
    require_root
    require_tools
    acquire_lock
    print_blue "======== 应用钉定 ${DOMAIN} ========"

    run_discovery || die "未发现任何候选 IP，已放弃，${HOSTS_FILE} 未改动。"
    print_measured
    select_best
    new_pin="${BEST%% *}"

    if [ "$(current_pin)" = "$new_pin" ]; then
        print_green "钉定 IP 无变化（${new_pin}），跳过写入。"
        flush_caches
        return 0
    fi

    cp -a "$HOSTS_FILE" "$HOSTS_FILE.cdn-pin.bak" || die "备份 ${HOSTS_FILE} 失败。"
    write_hosts_with_block "$(build_block "$new_pin")"

    if [ "$(current_pin)" = "$new_pin" ]; then
        flush_caches
        print_green "已写入 ${HOSTS_FILE}：${DOMAIN} -> ${new_pin}（备份: ${HOSTS_FILE}.cdn-pin.bak）"
        command -v getent >/dev/null 2>&1 \
            && printf "getent 解析结果: %s\n" "$(getent hosts "$DOMAIN" | head -n 1 | awk '{print $1}')"
    else
        cp -a "$HOSTS_FILE.cdn-pin.bak" "$HOSTS_FILE"
        die "回读校验失败，已恢复备份。"
    fi
}

cmd_status() {
    local pinned sys_ip
    require_tools
    print_blue "======== 状态 ========"

    pinned="$(current_pin)"
    if [ -n "$pinned" ]; then
        printf "当前钉定: %-16s ping %s ms\n" "$pinned" "$(ping_avg "$pinned" | { grep . || printf '不通'; })"
    else
        print_yellow "当前未钉定（${HOSTS_FILE} 中无 cdn-pin 标记块）。"
    fi

    sys_ip="$(dig +short +time=3 +tries=1 A "$DOMAIN" 2>/dev/null | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -n 1)"
    if [ -n "$sys_ip" ]; then
        printf "系统解析: %-16s ping %s ms\n" "$sys_ip" "$(ping_avg "$sys_ip" | { grep . || printf '不通'; })"
    else
        print_yellow "系统解析失败（DNS 查询无结果）。"
    fi

    command -v getent >/dev/null 2>&1 \
        && printf "系统生效: %s\n" "$(getent hosts "$DOMAIN" | head -n 1 | awk '{print $1}')"
    printf "ECS 前缀: %s\n" "$ECS_PREFIX"
}

cmd_rollback() {
    require_root
    acquire_lock
    print_blue "======== 回滚 ========"

    grep -qF "$MARK_BEGIN" "$HOSTS_FILE" 2>/dev/null \
        || { print_yellow "未找到钉定条目，无需回滚。"; return 0; }

    cp -a "$HOSTS_FILE" "$HOSTS_FILE.cdn-pin.bak" || die "备份 ${HOSTS_FILE} 失败。"
    write_hosts_with_block ""
    flush_caches
    print_green "已移除钉定条目，恢复系统解析。（备份: ${HOSTS_FILE}.cdn-pin.bak）"
}

case "${1:-}" in
    preview) cmd_preview ;;
    apply) cmd_apply ;;
    status) cmd_status ;;
    rollback) cmd_rollback ;;
    *)
        print_red "用法: $0 preview | apply | status | rollback"
        exit 1
        ;;
esac
