#!/bin/bash
# blacklist_updater.sh - загружает и применяет чёрный список из C24Be

set -e

BLACKLIST_DIR="/var/log/blacklist"
OLD_FILE="${BLACKLIST_DIR}/old_blacklist.txt"
NEW_FILE="${BLACKLIST_DIR}/blacklist.txt"
LOG_FILE="${BLACKLIST_DIR}/blacklist_updater.log"
SOURCE_URL="https://github.com/C24Be/AS_Network_List/raw/main/blacklists/blacklist.txt"

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

is_ipv4() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; }
is_ipv6() { [[ "$1" =~ : ]]; }

mkdir -p "$BLACKLIST_DIR"

if [ -f "$NEW_FILE" ]; then
    mv "$NEW_FILE" "$OLD_FILE"
fi

echo "Загрузка списка из $SOURCE_URL ..."
if ! wget --no-verbose -O "$NEW_FILE" "$SOURCE_URL"; then
    echo "Ошибка загрузки" | tee -a "$LOG_FILE"
    exit 1
fi

dos2unix "$NEW_FILE" 2>/dev/null || sed -i 's/\r$//' "$NEW_FILE"

TOTAL_LINES=$(wc -l < "$NEW_FILE")
echo "Загружено строк: $TOTAL_LINES"
log "Загружено строк: $TOTAL_LINES"

declare -A old_ipv4 old_ipv6
if [ -f "$OLD_FILE" ]; then
    while IFS= read -r addr; do
        [ -z "$addr" ] && continue
        is_ipv4 "$addr" && old_ipv4["$addr"]=1
        is_ipv6 "$addr" && old_ipv6["$addr"]=1
    done < "$OLD_FILE"
fi

declare -A new_ipv4 new_ipv6
while IFS= read -r addr; do
    [ -z "$addr" ] && continue
    is_ipv4 "$addr" && new_ipv4["$addr"]=1
    is_ipv6 "$addr" && new_ipv6["$addr"]=1
done < "$NEW_FILE"

echo "Найдено IPv4: ${#new_ipv4[@]}, IPv6: ${#new_ipv6[@]}"
log "Найдено IPv4: ${#new_ipv4[@]}, IPv6: ${#new_ipv6[@]}"

added=0
for addr in "${!new_ipv4[@]}"; do
    if ! iptables -t raw -C PREROUTING -s "$addr" -j DROP &>/dev/null; then
        iptables -t raw -A PREROUTING -s "$addr" -j LOG --log-prefix "Blocked IP attempt: "
        iptables -t raw -A PREROUTING -s "$addr" -j DROP
        ((added++))
    fi
done

for addr in "${!new_ipv6[@]}"; do
    if ! ip6tables -t raw -C PREROUTING -s "$addr" -j DROP &>/dev/null; then
        ip6tables -t raw -A PREROUTING -s "$addr" -j LOG --log-prefix "Blocked IP attempt: "
        ip6tables -t raw -A PREROUTING -s "$addr" -j DROP
        ((added++))
    fi
done

removed=0
if [ -f "$OLD_FILE" ]; then
    for addr in "${!old_ipv4[@]}"; do
        if [ -z "${new_ipv4[$addr]}" ]; then
            iptables -t raw -D PREROUTING -s "$addr" -j LOG --log-prefix "Blocked IP attempt: " 2>/dev/null
            iptables -t raw -D PREROUTING -s "$addr" -j DROP 2>/dev/null
            ((removed++))
        fi
    done
    for addr in "${!old_ipv6[@]}"; do
        if [ -z "${new_ipv6[$addr]}" ]; then
            ip6tables -t raw -D PREROUTING -s "$addr" -j LOG --log-prefix "Blocked IP attempt: " 2>/dev/null
            ip6tables -t raw -D PREROUTING -s "$addr" -j DROP 2>/dev/null
            ((removed++))
        fi
    done
fi

iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

echo "Добавлено: $added | Удалено: $removed"
log "Добавлено: $added, Удалено: $removed"
