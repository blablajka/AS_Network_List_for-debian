#!/bin/bash
# ============================================================
# Название:     blacklist_updater.sh
# Назначение:    Загружает чёрный список сетей из репозитория C24Be
#                и добавляет их в iptables/ip6tables (таблица raw)
#                Автоматически настраивает cron для ежедневного обновления.
# Автор:        blablajka
# Версия:       3.0 (с автоустановкой cron)
# ============================================================

set -e

# --- Конфигурация ---
BLACKLIST_DIR="/var/log/blacklist"
OLD_FILE="${BLACKLIST_DIR}/old_blacklist.txt"
NEW_FILE="${BLACKLIST_DIR}/blacklist.txt"
LOG_FILE="${BLACKLIST_DIR}/blacklist_updater.log"
SOURCE_URL="https://github.com/C24Be/AS_Network_List/raw/main/blacklists/blacklist.txt"

# --- Функция логирования ---
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

# --- 1. Автоматическая настройка cron (ещё до основной работы) ---
setup_cron() {
    # Устанавливаем cron, если не установлен
    if ! command -v crontab >/dev/null 2>&1; then
        echo "cron не найден, устанавливаю..."
        apt update && apt install -y cron
        systemctl enable cron --now
    fi

    # Проверяем, есть ли уже задание
    if ! crontab -l 2>/dev/null | grep -q "$0"; then
        echo "Добавляю задание в cron (ежедневно в 9:00)"
        (crontab -l 2>/dev/null; echo "0 9 * * * $0") | crontab -
        log "Добавлено задание в cron: 0 9 * * * $0"
    else
        log "Задание в cron уже существует"
    fi
}

# --- 2. Основная работа ---

# Вызываем настройку cron (только если скрипт запущен от root)
if [ "$EUID" -eq 0 ]; then
    setup_cron
fi

mkdir -p "$BLACKLIST_DIR"

# Бэкап старого списка
if [ -f "$NEW_FILE" ]; then
    mv "$NEW_FILE" "$OLD_FILE"
fi

# Загрузка нового списка
echo "Загрузка чёрного списка из $SOURCE_URL ..."
if ! wget --no-verbose -O "$NEW_FILE" "$SOURCE_URL"; then
    echo "Ошибка: не удалось загрузить список." | tee -a "$LOG_FILE"
    exit 1
fi

# Удаляем символы \r
dos2unix "$NEW_FILE" 2>/dev/null || sed -i 's/\r$//' "$NEW_FILE"

TOTAL_LINES=$(wc -l < "$NEW_FILE")
echo "Загружено строк: $TOTAL_LINES"
log "Загружено строк: $TOTAL_LINES"

# Функции определения типа адреса
is_ipv4() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; }
is_ipv6() { [[ "$1" =~ : ]]; }

# Чтение старых адресов
declare -A old_ipv4 old_ipv6
if [ -f "$OLD_FILE" ]; then
    while IFS= read -r addr; do
        [ -z "$addr" ] && continue
        if is_ipv4 "$addr"; then
            old_ipv4["$addr"]=1
        elif is_ipv6 "$addr"; then
            old_ipv6["$addr"]=1
        fi
    done < "$OLD_FILE"
fi

# Чтение новых адресов
declare -A new_ipv4 new_ipv6
while IFS= read -r addr; do
    [ -z "$addr" ] && continue
    if is_ipv4 "$addr"; then
        new_ipv4["$addr"]=1
    elif is_ipv6 "$addr"; then
        new_ipv6["$addr"]=1
    fi
done < "$NEW_FILE"

echo "Найдено IPv4: ${#new_ipv4[@]}, IPv6: ${#new_ipv6[@]}"
log "Найдено IPv4: ${#new_ipv4[@]}, IPv6: ${#new_ipv6[@]}"

# Добавление новых правил
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

# Удаление устаревших правил
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

# Сохранение правил
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

echo "Добавлено: $added | Удалено: $removed"
log "Добавлено: $added, Удалено: $removed"

exit 0
