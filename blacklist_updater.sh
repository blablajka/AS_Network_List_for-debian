#!/bin/bash
# =============================================
# Улучшенный скрипт обновления blacklist (IPv4 + IPv6)
# =============================================

BLACKLIST_DIR="/var/log/blacklist"
NEW_V4="${BLACKLIST_DIR}/blacklist.txt"
NEW_V6="${BLACKLIST_DIR}/blacklist-v6.txt"

URL_V4="https://github.com/C24Be/AS_Network_List/raw/main/blacklists/blacklist.txt"
URL_V6="https://github.com/C24Be/AS_Network_List/raw/main/blacklists/blacklist-v6.txt"

mkdir -p "$BLACKLIST_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Запуск обновления blacklist..."

# Скачиваем свежие списки
wget --no-verbose -O "$NEW_V4" "$URL_V4"
wget --no-verbose -O "$NEW_V6" "$URL_V6"

# Убираем Windows-символы
sed -i 's/\r$//' "$NEW_V4" "$NEW_V6" 2>/dev/null

# Очистка старых правил
iptables -t raw -F PREROUTING
ip6tables -t raw -F PREROUTING

echo "Добавление IPv4 сетей..."
count=0
while read -r net; do
    [[ -z "$net" || "$net" =~ ^# ]] && continue
    ((count++))
    
    iptables -t raw -A PREROUTING -s "$net" -j LOG --log-prefix "Blocked IP attempt: " 2>/dev/null || true
    iptables -t raw -A PREROUTING -s "$net" -j DROP 2>/dev/null || true
done < "$NEW_V4"

echo "Добавление IPv6 сетей..."
while read -r net; do
    [[ -z "$net" || "$net" =~ ^# ]] && continue
    ip6tables -t raw -A PREROUTING -s "$net" -j LOG --log-prefix "Blocked IP attempt: " 2>/dev/null || true
    ip6tables -t raw -A PREROUTING -s "$net" -j DROP 2>/dev/null || true
done < "$NEW_V6"

# Сохранение правил
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

echo "=== Обновление завершено ==="
echo "IPv4 правил: $(iptables -t raw -L PREROUTING -n | grep -c DROP)"
echo "IPv6 правил: $(ip6tables -t raw -L PREROUTING -n | grep -c DROP)"
echo "Список обновлён: $(wc -l < "$NEW_V4") сетей IPv4"
EOF

# Делаем скрипт исполняемым
chmod +x /var/log/blacklist/blacklist_updater.sh

echo "Новый скрипт установлен!"
