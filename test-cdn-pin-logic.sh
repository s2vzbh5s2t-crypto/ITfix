#!/usr/bin/env bash
# 逻辑单元测试：在无 dig 的环境下验证 hosts 标记块增删、择优算法、写入/回读
# 运行方式: bash test-cdn-pin-logic.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOSTS_TMP="$(mktemp)"
trap 'rm -f "$HOSTS_TMP"' EXIT

export CDN_PIN_HOSTS="$HOSTS_TMP"

# 去掉末尾的 main 调用后 source，拿到全部函数定义
# shellcheck disable=SC1090
source <(sed '$d' "$SCRIPT_DIR/linux-toolbox.sh")

PASS=0
FAIL=0
check() {
    local desc="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        PASS=$((PASS + 1))
        printf "PASS: %s\n" "$desc"
    else
        FAIL=$((FAIL + 1))
        printf "FAIL: %s\n  got:  %s\n  want: %s\n" "$desc" "$got" "$want"
    fi
}

# ---- fixture：含旧标记块和普通条目的 hosts ----
cat >"$HOSTS_TMP" <<'EOF'
127.0.0.1   localhost
::1         localhost

# BEGIN cdn-pin
# 由 cdn-pin 生成：www.gstatic.com（ECS 43.129.0.0/24），请勿手动编辑
142.250.66.4   www.gstatic.com
# END cdn-pin
1.2.3.4    example.com
EOF

# ---- strip_block：删块保其余 ----
check "strip_block 删除标记块并保留其他条目" \
    "$(cdn_pin_strip_block "$HOSTS_TMP" | tr '\n' '|')" \
    "127.0.0.1   localhost|::1         localhost||1.2.3.4    example.com|"

# ---- current：读旧钉定 ----
check "cdn_pin_current 读取旧钉定 IP" "$(cdn_pin_current)" "142.250.66.4"

# ---- build_block + write 回环 ----
block="$(cdn_pin_build_block "142.251.200.1")"
cdn_pin_write_block "$block"
check "写入后 cdn_pin_current 回读正确" "$(cdn_pin_current)" "142.251.200.1"
check "普通条目未受影响" "$(grep -c 'example.com' "$HOSTS_TMP")" "1"
check "旧钉定 IP 已被替换" "$(grep -c '142.250.66.4' "$HOSTS_TMP")" "0"

# ---- 幂等：同一 block 再写一次，内容不变 ----
before="$(md5sum "$HOSTS_TMP" | cut -d' ' -f1)"
cdn_pin_write_block "$block"
after="$(md5sum "$HOSTS_TMP" | cut -d' ' -f1)"
check "重复写入同一 block 幂等" "$after" "$before"

# ---- 回滚：写空 block 即删除 ----
cdn_pin_write_block ""
check "回滚后无钉定条目" "$(cdn_pin_current)" ""
check "回滚后标记块不存在" "$(grep -c 'cdn-pin' "$HOSTS_TMP")" "0"
check "回滚后 example.com 仍在" "$(grep -c 'example.com' "$HOSTS_TMP")" "1"

# ---- 择优算法 ----
measured="9.9.9.9 50
142.251.0.1 12.3
142.251.0.2 -
142.251.0.3 30"
check "pick_best 选延迟最低" "$(printf '%s\n' "$measured" | cdn_pin_pick_best)" "142.251.0.1 12.3"
check "全部不通时 pick_best 无输出" \
    "$(printf '1.1.1.1 -\n2.2.2.2 -\n' | cdn_pin_pick_best)" ""

# ---- 平均延迟解析（iputils 与 busybox 两种输出格式） ----
parse_rtt() { printf '%s\n' "$1" | grep -oE '[0-9.]+/[0-9.]+/[0-9.]+' | head -n 1 | cut -d/ -f2; }
check "解析 iputils 格式" \
    "$(parse_rtt 'rtt min/avg/max/mdev = 10.1/12.5/14.9/0.3 ms')" "12.5"
check "解析 busybox 格式" \
    "$(parse_rtt 'round-trip min/avg/max = 20.4/21.2/22.8 ms')" "21.2"

printf "\n结果: PASS=%d FAIL=%d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
