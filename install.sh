#!/bin/bash
# install.sh – полная автоматическая установка (IP-сети + домены)
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Полная установка блокировок для Debian ===${NC}"

# 1. Базовая настройка
echo -e "${BLUE}[1/6] Установка пакетов...${NC}"
apt update
apt install -y wget dos2unix iptables iptables-persistent rsyslog cron curl ipset dnsutils

echo -e "${BLUE}[2/6] Настройка iptables-legacy...${NC}"
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

echo -e "${BLUE}[3/6] Создание каталога /var/log/blacklist...${NC}"
mkdir -p /var/log/blacklist
if id "syslog" &>/dev/null; then
    chown syslog:adm /var/log/blacklist
else
    chown root:adm /var/log/blacklist
fi
chmod 0755 /var/log/blacklist

echo -e "${BLUE}[4/6] Настройка rsyslog...${NC}"
echo ':msg, contains, "Blocked IP attempt: " /var/log/blacklist/blacklist.log' > /etc/rsyslog.d/99-blacklist.conf
systemctl restart rsyslog

# 2. Блокировка IP-сетей (основной список)
echo -e "${BLUE}[5/6] Установка блокировки IP-сетей...${NC}"
wget -qO /var/log/blacklist/blacklist_updater.sh \
    https://raw.githubusercontent.com/blablajka/AS_Network_List_for-debian/main/blacklist_updater.sh
chmod +x /var/log/blacklist/blacklist_updater.sh
/var/log/blacklist/blacklist_updater.sh
(crontab -l 2>/dev/null; echo "0 9 * * * /var/log/blacklist/blacklist_updater.sh") | crontab -

# 3. Блокировка доменов
echo -e "${BLUE}[6/6] Установка блокировки доменов...${NC}"
wget -qO /usr/local/bin/domain_blocker.sh \
    https://raw.githubusercontent.com/blablajka/AS_Network_List_for-debian/main/domain_blocker.sh
chmod +x /usr/local/bin/domain_blocker.sh
wget -qO /var/log/blacklist/domains.list \
    https://raw.githubusercontent.com/blablajka/AS_Network_List_for-debian/main/domains.list

/usr/local/bin/domain_blocker.sh --install

# Сохраняем правила
netfilter-persistent save

echo -e "${GREEN}=== Установка завершена ===${NC}"
echo "Статус IP-блокировки: /var/log/blacklist/blacklist_updater.sh --status"
echo "Статус доменов:        /usr/local/bin/domain_blocker.sh --status"
echo "Лог блокировок:        tail -f /var/log/blacklist/blacklist.log"
