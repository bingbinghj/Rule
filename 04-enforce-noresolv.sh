#!/bin/sh
# 安装持久化的忽略解析文件服务：开机执行，并每分钟检查一次。
# 只在 noresolv 不是1时写入配置并重载dnsmasq。
set -eu
umask 077

NORESOLV_DIR=${NORESOLV_ETC_DIR:-/etc}
NORESOLV_SCRIPT="$NORESOLV_DIR/init.d/enforce-noresolv"
NORESOLV_LINK="$NORESOLV_DIR/rc.d/S99enforce-noresolv"
NORESOLV_BACKUP="$NORESOLV_DIR/sysupgrade.conf"
NORESOLV_TMP=
noresolv_cleanup() {
    [ -z "$NORESOLV_TMP" ] || rm -f "$NORESOLV_TMP"
}
trap noresolv_cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$NORESOLV_DIR/init.d" "$NORESOLV_DIR/rc.d"

NORESOLV_TMP=$(mktemp "$NORESOLV_DIR/init.d/.noresolv.XXXXXX")
cat > "$NORESOLV_TMP" <<'NORESOLV_SERVICE'
#!/bin/sh /etc/rc.common
START=99

start() {
    if [ "$(uci -q get 'dhcp.@dnsmasq[0]')" != dnsmasq ]; then
        logger -t enforce-noresolv '未找到主dnsmasq配置，未修改任何设置。'
        return 1
    fi
    [ "$(uci -q get 'dhcp.@dnsmasq[0].noresolv')" != 1 ] || return 0
    uci -q set 'dhcp.@dnsmasq[0].noresolv=1' || return 1
    uci -q commit dhcp || return 1
    if /etc/init.d/dnsmasq reload; then
        logger -t enforce-noresolv '已设置noresolv=1并重载dnsmasq。'
    else
        logger -t enforce-noresolv 'noresolv=1已保存，dnsmasq重载失败，请检查服务。'
        return 1
    fi
}

boot() {
    start "$@"
}
NORESOLV_SERVICE
chmod 0755 "$NORESOLV_TMP"
mv -f "$NORESOLV_TMP" "$NORESOLV_SCRIPT"
NORESOLV_TMP=

# Explicitly retain the service, boot link and its configuration across sysupgrade.
touch "$NORESOLV_BACKUP"
if [ -s "$NORESOLV_BACKUP" ] && [ -n "$(tail -c 1 "$NORESOLV_BACKUP")" ]; then
    printf '\n' >> "$NORESOLV_BACKUP"
fi
for noresolv_path in \
    "$NORESOLV_SCRIPT" "$NORESOLV_LINK" \
    "$NORESOLV_DIR/config/dhcp" "$NORESOLV_DIR/crontabs/root" \
    "$NORESOLV_BACKUP"; do
    grep -Fqx "$noresolv_path" "$NORESOLV_BACKUP" || printf '%s\n' "$noresolv_path" >> "$NORESOLV_BACKUP"
done

"$NORESOLV_SCRIPT" enable
NORESOLV_TMP=$(mktemp)
if ! crontab -l > "$NORESOLV_TMP" 2>/dev/null; then
    [ ! -f "$NORESOLV_DIR/crontabs/root" ] || {
        printf '无法读取已有root定时任务，停止安装以保留现有任务。\n' >&2
        exit 1
    }
    : > "$NORESOLV_TMP"
fi
sed -i '/#enforce-noresolv$/d' "$NORESOLV_TMP"
printf '* * * * * %s start >/dev/null 2>&1 #enforce-noresolv\n' "$NORESOLV_SCRIPT" >> "$NORESOLV_TMP"
crontab "$NORESOLV_TMP"
rm -f "$NORESOLV_TMP"
NORESOLV_TMP=
"$NORESOLV_SCRIPT" start
printf '已安装 %s；开机执行并每分钟检查，保留配置升级时纳入备份。\n' "$NORESOLV_SCRIPT"
