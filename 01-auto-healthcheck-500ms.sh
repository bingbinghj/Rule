#!/bin/sh
# 将本文件内容追加到内置 openclash_custom_overwrite.sh 的 exit 0 前。
# 原健康检查INI保持启用；本文件只安装监测任务，不重启OpenClash或cron。

hc500_install() {
    hc500_dir=${HC500_CUSTOM_DIR:-/etc/openclash/custom}
    mkdir -p "$hc500_dir" || return 1
    hc500_script="$hc500_dir/openclash_hc500.sh"
    hc500_tmp=$(mktemp "$hc500_dir/.hc500.XXXXXX") || return 1

    cat > "$hc500_tmp" <<'HC500_WORKER'
#!/bin/sh
# 检查组内最新测速值：超过500ms或超时/失败触发；500ms本身不触发。
HC500_GROUP=${HC500_GROUP:-'🚀 节点选择'}
HC500_THRESHOLD=500
HC500_COOLDOWN=300
HC500_TEST_URL=https://www.gstatic.com/generate_204
HC500_ROOT=${HC500_TMPROOT:-/tmp}
HC500_OVERWRITES=${HC500_OVERWRITE_DIR:-/etc/openclash/overwrite}
umask 077

hc500_module_enabled() {
    hc500_sections=$(uci -q show openclash 2>/dev/null |
        sed -n 's/^\(openclash\.[^=]*\)=config_overwrite$/\1/p')
    for hc500_section in $hc500_sections; do
        [ "$(uci -q get "$hc500_section.enable")" = 1 ] || continue
        hc500_name=$(uci -q get "$hc500_section.name")
        case "$hc500_name" in ''|*/*) continue ;; esac
        [ -f "$HC500_OVERWRITES/$hc500_name" ] || continue
        grep -q '^# hc500-auto-healthcheck$' "$HC500_OVERWRITES/$hc500_name" || continue
        hc500_matches=$(uci -q get "$hc500_section.config")
        case " $hc500_matches " in
            *' all '*|*" $HC500_CONFIG "*) return 0 ;;
        esac
    done
    return 1
}

for hc500_command in uci curl jsonfilter ruby sed tail; do
    command -v "$hc500_command" >/dev/null 2>&1 || exit 0
done
[ "$(uci -q get openclash.config.enable)" = 1 ] || exit 0
HC500_CONFIG=$(uci -q get openclash.config.config_path)
[ -n "$HC500_CONFIG" ] || exit 0
hc500_module_enabled || exit 0

HC500_LOCK="$HC500_ROOT/openclash-hc500.lock"
HC500_STATE="$HC500_ROOT/openclash-hc500.state"
if ! mkdir "$HC500_LOCK" 2>/dev/null; then
    # A terminated job must not leave the monitor locked until reboot.
    sleep 1
    hc500_owner=$(cat "$HC500_LOCK/pid" 2>/dev/null)
    case "$hc500_owner" in
        ''|*[!0-9]*) ;;
        *) kill -0 "$hc500_owner" 2>/dev/null && exit 0 ;;
    esac
    rm -f "$HC500_LOCK/pid"
    rmdir "$HC500_LOCK" 2>/dev/null || exit 0
    mkdir "$HC500_LOCK" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" > "$HC500_LOCK/pid"
HC500_WORK=$(mktemp -d "$HC500_ROOT/openclash-hc500.XXXXXX") || {
    rm -f "$HC500_LOCK/pid"
    rmdir "$HC500_LOCK"
    exit 0
}
hc500_cleanup() {
    rm -f "$HC500_WORK/proxies" "$HC500_WORK/members" "$HC500_WORK/result"
    rmdir "$HC500_WORK" 2>/dev/null
    rm -f "$HC500_LOCK/pid"
    rmdir "$HC500_LOCK" 2>/dev/null
}
trap hc500_cleanup EXIT
trap 'exit 0' HUP INT TERM

hc500_now=$(date +%s)
hc500_last=$(sed -n '1p' "$HC500_STATE" 2>/dev/null)
hc500_last_key=$(sed -n '2p' "$HC500_STATE" 2>/dev/null)
hc500_key="$HC500_CONFIG|$HC500_GROUP"
case "$hc500_last" in
    ''|*[!0-9]*) ;;
    *) if [ "$hc500_last_key" = "$hc500_key" ] &&
          [ "$hc500_now" -ge "$hc500_last" ] &&
          [ "$((hc500_now - hc500_last))" -lt "$HC500_COOLDOWN" ]; then
           exit 0
       fi ;;
esac

hc500_port=$(uci -q get openclash.config.cn_port)
case "$hc500_port" in ''|*[!0-9]*) exit 0 ;; esac
[ "$hc500_port" -ge 1 ] && [ "$hc500_port" -le 65535 ] || exit 0
hc500_secret=$(uci -q get openclash.config.dashboard_password)
hc500_api="http://127.0.0.1:$hc500_port"
hc500_code=$(curl -sS --noproxy '*' --connect-timeout 2 --max-time 12 \
    -H "Authorization: Bearer $hc500_secret" \
    -o "$HC500_WORK/proxies" -w '%{http_code}' "$hc500_api/proxies" 2>/dev/null) || exit 0
[ "$hc500_code" = 200 ] || exit 0

# JSON-path names and URL-path names require different escaping.
hc500_json_name() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
hc500_group_key=$(hc500_json_name "$HC500_GROUP")
hc500_url_key=$(hc500_json_name "$HC500_TEST_URL")
jsonfilter -i "$HC500_WORK/proxies" \
    -e "@.proxies[\"$hc500_group_key\"].all[*]" \
    > "$HC500_WORK/members" 2>/dev/null || exit 0
hc500_bad_delay=
hc500_bad_reason=
while IFS= read -r hc500_member; do
    hc500_member_key=$(hc500_json_name "$hc500_member")
    hc500_delay=$(jsonfilter -i "$HC500_WORK/proxies" \
        -e "@.proxies[\"$hc500_member_key\"].extra[\"$hc500_url_key\"].history[*].delay" 2>/dev/null | tail -n 1)
    if [ -z "$hc500_delay" ]; then
        hc500_delay=$(jsonfilter -i "$HC500_WORK/proxies" \
            -e "@.proxies[\"$hc500_member_key\"].history[*].delay" 2>/dev/null | tail -n 1)
    fi
    case "$hc500_delay" in ''|*[!0-9]*) continue ;; esac
    # Mihomo records a failed/timeout test as delay=0. Empty history is untested.
    if [ "$hc500_delay" -eq 0 ]; then
        hc500_bad_delay=0
        hc500_bad_reason='测速超时或失败'
        break
    elif [ "$hc500_delay" -gt "$HC500_THRESHOLD" ]; then
        hc500_bad_delay=$hc500_delay
        hc500_bad_reason="延迟${hc500_delay}ms"
        break
    fi
done < "$HC500_WORK/members"
[ -n "$hc500_bad_delay" ] || exit 0

# Only this group is retested; the Selector API keeps its manual selection.
hc500_group_path=$(ruby -e 'print ARGV[0].bytes.map { |b| "%%%02X" % b }.join' "$HC500_GROUP") || exit 0
printf '%s\n%s\n' "$hc500_now" "$hc500_key" > "$HC500_STATE"
hc500_code=$(curl -sS --noproxy '*' --connect-timeout 2 --max-time 12 \
    -H "Authorization: Bearer $hc500_secret" --get \
    --data-urlencode "url=$HC500_TEST_URL" --data-urlencode timeout=5000 \
    --data-urlencode expected=204 \
    -o "$HC500_WORK/result" -w '%{http_code}' \
    "$hc500_api/group/$hc500_group_path/delay" 2>/dev/null) || hc500_code=000
if [ "$hc500_code" = 200 ]; then
    logger -t openclash-hc500 "节点选择条目${hc500_bad_reason}，已重新测速整组；冷却${HC500_COOLDOWN}秒。"
else
    logger -t openclash-hc500 "节点选择重测未完成（HTTP ${hc500_code}）；冷却${HC500_COOLDOWN}秒后再检查。"
fi
HC500_WORKER

    chmod 0755 "$hc500_tmp" || { rm -f "$hc500_tmp"; return 1; }
    mv -f "$hc500_tmp" "$hc500_script" || { rm -f "$hc500_tmp"; return 1; }
    hc500_cron=$(mktemp) || return 1
    crontab -l 2>/dev/null | sed '/#openclash-hc500$/d' > "$hc500_cron"
    printf '* * * * * %s >/dev/null 2>&1 #openclash-hc500\n' "$hc500_script" >> "$hc500_cron"
    crontab "$hc500_cron"
    hc500_result=$?
    rm -f "$hc500_cron"
    return "$hc500_result"
}

hc500_install || logger -t openclash-hc500 '无法安装500ms重测任务，请检查自定义目录与crontab。'
