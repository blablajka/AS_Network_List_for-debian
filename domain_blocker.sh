cat > /usr/local/bin/domain_blocker.sh << 'EOF'
#!/bin/bash
IPSET4="blocked_domains4"
DOMAINS_FILE="/var/log/blacklist/domains.list"

# Удаляем правило iptables, если оно есть
iptables -D OUTPUT -m set --match-set $IPSET4 dst -j DROP 2>/dev/null

# Удаляем старый ipset и создаём новый
ipset destroy $IPSET4 2>/dev/null
ipset create $IPSET4 hash:ip maxelem 100000

# Заполняем IP-адресами
while IFS= read -r domain; do
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue
    for ip in $(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9.]+$'); do
        ipset add $IPSET4 $ip -exist
    done
done < "$DOMAINS_FILE"

COUNT=$(ipset list $IPSET4 | grep -c '^add')
echo "Заблокировано IPv4: $COUNT"

# Добавляем правило iptables обратно
iptables -I OUTPUT -m set --match-set $IPSET4 dst -j DROP

# Сохраняем
iptables-save > /etc/iptables/rules.v4
EOF

chmod +x /usr/local/bin/domain_blocker.sh
