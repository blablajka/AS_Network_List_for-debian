#!/bin/bash
# domain_blocker.sh – блокировка доменов через ipset/iptables
set -euo pipefail

IPSET_NAME="blocked_domains"
DOMAINS_FILE="/var/log/blacklist/domains.list"   # файл в общей папке
LOG_FILE="/var/log/domain_blocker.log"
CRON_TIME="5 9 * * *"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Ошибка: запустите от root.${NC}"
        exit 1
    fi
}

check_deps() {
    for dep in ipset iptables dig; do
        if ! command -v "$dep" &>/dev/null; then
            echo -e "${YELLOW}Устанавливаю $dep...${NC}"
            apt update && apt install -y ipset dnsutils iptables
            break
        fi
    done
}

setup_cron() {
    local script_path=$(realpath "$0")
    if ! crontab -l 2>/dev/null | grep -qF "$script_path --update"; then
        (crontab -l 2>/dev/null; echo "$CRON_TIME $script_path --update") | crontab -
        echo -e "${GREEN}Cron задание добавлено (9:05).${NC}"
        log "Cron added"
    fi
}

update_ipset() {
    echo -e "${BLUE}Обновление списка IP для доменов...${NC}"
    local tmp=$(mktemp)
    [ ! -f "$DOMAINS_FILE" ] && { echo -e "${RED}Нет файла $DOMAINS_FILE${NC}"; exit 1; }

    grep -vE '^\s*#' "$DOMAINS_FILE" | grep -vE '^\s*$' | while read -r domain; do
        echo -n "  $domain ... "
        dig +short A "$domain" 2>/dev/null | grep -E '^[0-9.]+$' >> "$tmp"
        dig +short AAAA "$domain" 2>/dev/null | grep -E '^[0-9a-fA-F:]+$' >> "$tmp"
        echo "OK"
    done

    ipset create "$IPSET_NAME" hash:net -exist 2>/dev/null || true
    ipset flush "$IPSET_NAME"
    while read -r ip; do [ -n "$ip" ] && echo "add $IPSET_NAME $ip"; done < "$tmp" | ipset restore -exist
    local count=$(ipset list "$IPSET_NAME" | grep -c '^add')
    echo -e "${GREEN}Заблокировано $count IP/сетей.${NC}"
    log "Updated: $count entries"
    rm -f "$tmp"
}

setup_iptables() {
    if ! iptables -C OUTPUT -m set --match-set "$IPSET_NAME" dst -j DROP 2>/dev/null; then
        iptables -I OUTPUT -m set --match-set "$IPSET_NAME" dst -j DROP
        echo -e "${GREEN}Правило iptables добавлено.${NC}"
        log "iptables rule added"
        netfilter-persistent save
    fi
}

remove_iptables() {
    if iptables -C OUTPUT -m set --match-set "$IPSET_NAME" dst -j DROP 2>/dev/null; then
        iptables -D OUTPUT -m set --match-set "$IPSET_NAME" dst -j DROP
        echo -e "${GREEN}Правило iptables удалено.${NC}"
        netfilter-persistent save
    fi
}

remove_cron() {
    local script_path=$(realpath "$0")
    if crontab -l 2>/dev/null | grep -qF "$script_path --update"; then
        crontab -l 2>/dev/null | grep -vF "$script_path --update" | crontab -
        echo -e "${GREEN}Cron задание удалено.${NC}"
    fi
}

status() {
    echo -e "${BLUE}=== Статус блокировки доменов ===${NC}"
    if ipset list "$IPSET_NAME" &>/dev/null; then
        echo "  ipset: $IPSET_NAME ($(ipset list "$IPSET_NAME" | grep -c '^add') записей)"
    else
        echo "  ipset: не существует"
    fi
    iptables -C OUTPUT -m set --match-set "$IPSET_NAME" dst -j DROP 2>/dev/null && echo "  iptables: правило активно" || echo "  iptables: правило отсутствует"
    crontab -l 2>/dev/null | grep -qF "$(realpath "$0") --update" && echo "  cron: задание есть" || echo "  cron: задания нет"
    [ -f "$LOG_FILE" ] && echo -e "\nПоследние логи:" && tail -3 "$LOG_FILE"
}

case "$1" in
    --install)
        check_root; check_deps; update_ipset; setup_iptables; setup_cron
        echo -e "${GREEN}Блокировка доменов установлена.${NC}"
        ;;
    --update)
        check_root; check_deps; update_ipset
        ;;
    --remove)
        check_root; remove_iptables; remove_cron
        ipset destroy "$IPSET_NAME" 2>/dev/null && echo -e "${GREEN}ipset удалён.${NC}"
        ;;
    --status)
        status
        ;;
    *)
        echo "Использование: $0 {--install|--update|--remove|--status}"
        exit 1
        ;;
esac
