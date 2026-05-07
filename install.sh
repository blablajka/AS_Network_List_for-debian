#!/bin/bash
set -e

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Создаём рабочую директорию
mkdir -p /var/log/blacklist

# Определяем URL основного скрипта
BASE_URL="https://raw.githubusercontent.com/blablajka/AS_Network_List_for-debian/main"
MAIN_SCRIPT_URL="${BASE_URL}/blacklist_updater.sh"

# Загружаем основной скрипт
echo -e "${GREEN}Downloading blacklist_updater.sh...${NC}"
wget -q --show-progress -O /var/log/blacklist/blacklist_updater.sh "$MAIN_SCRIPT_URL"
chmod +x /var/log/blacklist/blacklist_updater.sh

# Запускаем его
echo -e "${GREEN}Starting the main script...${NC}"
exec /var/log/blacklist/blacklist_updater.sh
