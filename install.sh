#!/bin/bash
# install.sh - одноразовый установщик для blacklist_updater.sh
set -e

echo "=== Установка Blacklist Updater для Debian ==="

# 1. Базовые пакеты
apt update
apt install -y wget dos2unix iptables iptables-persistent rsyslog cron

# 2. Переключение на iptables-legacy
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# 3. Создание каталога и прав (без ошибок)
mkdir -p /var/log/blacklist
if id "syslog" &>/dev/null; then
    chown syslog:adm /var/log/blacklist
else
    chown root:adm /var/log/blacklist
fi
chmod 0755 /var/log/blacklist

# 4. Загрузка основного скрипта из репозитория
wget -qO /var/log/blacklist/blacklist_updater.sh \
    https://raw.githubusercontent.com/blablajka/AS_Network_List_for-debian/main/blacklist_updater.sh
chmod +x /var/log/blacklist/blacklist_updater.sh

# 5. Настройка rsyslog для отдельного лога блокировок
echo ':msg, contains, "Blocked IP attempt: " /var/log/blacklist/blacklist.log' > /etc/rsyslog.d/99-blacklist.conf
systemctl restart rsyslog

# 6. Первый запуск
/var/log/blacklist/blacklist_updater.sh

# 7. Сохранение правил
netfilter-persistent save

echo "=== Установка завершена ==="
echo "Чёрный список будет обновляться ежедневно в 9:00"
echo "Лог блокировок: /var/log/blacklist/blacklist.log"
