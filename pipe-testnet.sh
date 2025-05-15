#!/bin/bash

# Pipe Network Testnet скрипт установки и управления

# Проверяем, запущен ли скрипт от имени root
if [ "$EUID" -ne 0 ]; then 
    echo "Пожалуйста, запустите скрипт с правами root (используйте sudo)"
    exit 1
fi

# Назначаем права на выполнение текущему скрипту
chmod 755 "$0"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Директории для логов и резервных копий
LOG_FILE="/var/log/pipe_testnet_install.log"
BACKUP_DIR="/root/pipe_node_backup"

# Функция для логирования
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
    echo -e "$message"
}

# Функция для отображения главного меню
show_menu() {
    clear
    echo -e "${BLUE}=== Pipe Network Testnet - Управление нодой ===${NC}"
    echo -e "${GREEN}Присоединяйтесь к нашему Telegram каналу: ${BLUE}@nodetrip${NC}"
    echo -e "${GREEN}Гайды по нодам, новости, обновления и помощь${NC}"
    echo "------------------------------------------------"
    echo "1. Установить ноду Testnet"
    echo "2. Мониторинг ноды"
    echo "3. Удалить ноду"
    echo "4. Создать резервную копию данных ноды"
    echo "5. Восстановить ноду из резервной копии"
    echo "6. Просмотреть логи установки"
    echo "7. Диагностика проблем запуска ноды"
    echo "8. Остановить ноду Devnet (если запущена)"
    echo "0. Выход"
    echo
}

# Функция для просмотра логов
show_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}=== Логи установки ===${NC}"
        cat "$LOG_FILE"
        echo
        echo -e "${BLUE}Логи сохранены в файле: $LOG_FILE${NC}"
    else
        echo -e "${RED}Файл логов не найден${NC}"
    fi
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция для остановки ноды devnet
stop_devnet_node() {
    echo -e "${YELLOW}Проверяем наличие ноды Devnet...${NC}"
    
    if systemctl is-active --quiet pop.service; then
        echo -e "${YELLOW}Останавливаем ноду Pipe Network Devnet...${NC}"
        systemctl stop pop.service
        systemctl disable pop.service
        echo -e "${GREEN}Нода Pipe Network Devnet остановлена и отключена${NC}"
    else
        echo -e "${BLUE}Активная нода Pipe Network Devnet не найдена${NC}"
    fi
    
    # Также проверяем сервис pipe-pop на всякий случай
    if systemctl is-active --quiet pipe-pop.service; then
        echo -e "${YELLOW}Останавливаем альтернативную ноду Pipe Network Devnet...${NC}"
        systemctl stop pipe-pop.service
        systemctl disable pipe-pop.service
        echo -e "${GREEN}Альтернативная нода Pipe Network Devnet остановлена и отключена${NC}"
    fi
    
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция для установки ноды testnet
install_testnet_node() {
    # Очищаем старые логи перед новой установкой
    log_message "${GREEN}Начинаем установку ноды Pipe Network Testnet...${NC}"
    
    # Проверяем, установлена ли уже нода
    if systemctl is-active --quiet popcache.service; then
        echo -e "${YELLOW}Служба popcache уже запущена. Хотите переустановить?${NC}"
        read -p "Переустановить ноду? (y/n): " choice
        if [[ $choice != "y" && $choice != "Y" ]]; then
            echo -e "${BLUE}Установка отменена.${NC}"
            return
        fi
        
        # Останавливаем службу
        systemctl stop popcache.service
        systemctl disable popcache.service
    fi
    
    # Проверка наличия старых данных Pipe
    OLD_NODE_INFO="/root/pipe/node_info.json"
    if [ -f "$OLD_NODE_INFO" ]; then
        echo -e "${YELLOW}Обнаружены данные от предыдущей установки Pipe.${NC}"
        echo -e "${BLUE}Создаем резервную копию...${NC}"
        mkdir -p "$BACKUP_DIR"
        cp "$OLD_NODE_INFO" "$BACKUP_DIR/node_info_backup_$(date +%Y%m%d_%H%M%S).json"
        echo -e "${GREEN}Резервная копия создана в $BACKUP_DIR${NC}"
    fi
    
    # Останавливаем службу старой ноды, если запущена
    if systemctl is-active --quiet pipe.service; then
        echo -e "${YELLOW}Останавливаем старую службу pipe...${NC}"
        systemctl stop pipe.service
        systemctl disable pipe.service
        systemctl daemon-reload
    fi
    
    # 1. Установка зависимостей
    echo -e "${BLUE}1. Устанавливаем необходимые зависимости...${NC}"
    apt update
    apt install -y libssl-dev ca-certificates
    
    # 2. Оптимизация производительности системы
    echo -e "${BLUE}2. Проверка и оптимизация настроек системы...${NC}"
    
    # Проверяем, были ли уже применены оптимизации
    if [ -f "/etc/sysctl.d/99-popcache.conf" ] && grep -q "net.ipv4.tcp_fastopen = 3" /etc/sysctl.d/99-popcache.conf; then
        echo -e "${GREEN}Оптимизации системы уже применены.${NC}"
    else
        # Применяем оптимизации
        cat > /etc/sysctl.d/99-popcache.conf << EOL
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 65535
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.core.wmem_max = 16777216
net.core.rmem_max = 16777216
EOL
        
        sysctl -p /etc/sysctl.d/99-popcache.conf
        
        # Проверяем, были ли уже применены оптимизации лимитов
        if [ ! -f "/etc/security/limits.d/popcache.conf" ] || ! grep -q "nofile 65535" /etc/security/limits.d/popcache.conf; then
            cat > /etc/security/limits.d/popcache.conf << EOL
*    hard nofile 65535
*    soft nofile 65535
EOL
            need_reboot=true
        fi
        
        if [ "$need_reboot" = true ]; then
            echo -e "${YELLOW}Были применены новые оптимизации системы.${NC}"
            echo -e "${YELLOW}Рекомендуется перезапустить терминал, а для VPS - перезагрузить его.${NC}"
            read -p "Хотите перезагрузить сервер сейчас? (y/n): " reboot_choice
            if [[ $reboot_choice == "y" || $reboot_choice == "Y" ]]; then
                reboot
                exit 0
            fi
        else
            echo -e "${GREEN}Все оптимизации системы успешно применены.${NC}"
        fi
    fi
    
    # Настройка фаервола
    echo -e "${BLUE}Настраиваем фаервол...${NC}"
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw reload
    
    # 3. Создание директорий
    echo -e "${BLUE}3. Создаем директории для ноды...${NC}"
    mkdir -p /opt/popcache
    mkdir -p /opt/popcache/logs
    cd /opt/popcache
    
    # 4. Загрузка бинарного файла
    echo -e "${BLUE}4. Загружаем бинарный файл Pipe Network...${NC}"
    
    # Автоматическая загрузка бинарного файла
    if [ ! -f /opt/popcache/pop-v0.3.0-linux-x64.tar.gz ]; then
        echo -e "${YELLOW}Загружаем бинарный файл с использованием вашего пригласительного кода...${NC}"
        
        # Пробуем разные методы загрузки
        DOWNLOAD_URL="https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz?invite=$invite_code"
        
        # Метод 1: wget с прогрессом
        echo -e "${YELLOW}Загрузка через wget...${NC}"
        wget -O /opt/popcache/pop-v0.3.0-linux-x64.tar.gz "$DOWNLOAD_URL"
        
        # Проверка успешности загрузки
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Пробуем альтернативный способ загрузки через curl...${NC}"
            
            # Метод 2: curl с имитацией браузера
            curl -L -A "Mozilla/5.0" "$DOWNLOAD_URL" -o /opt/popcache/pop-v0.3.0-linux-x64.tar.gz
            
            if [ $? -ne 0 ]; then
                echo -e "${RED}Не удалось автоматически загрузить файл.${NC}"
                echo -e "${YELLOW}Пожалуйста, загрузите файл вручную:${NC}"
                echo -e "${BLUE}1. Посетите https://download.pipe.network/ в браузере${NC}"
                echo -e "${BLUE}2. Введите ваш пригласительный код: ${YELLOW}$invite_code${NC}"
                echo -e "${BLUE}3. Загрузите файл pop-v0.3.0-linux-x64.tar.gz${NC}"
                echo -e "${BLUE}4. Загрузите его на сервер в директорию /opt/popcache${NC}"
                
                read -p "Продолжить установку после ручной загрузки? (y/n): " continue_manual
                if [[ $continue_manual != "y" && $continue_manual != "Y" ]]; then
                    return 1
                fi
            else
                echo -e "${GREEN}Бинарный файл успешно загружен через curl!${NC}"
            fi
        else
            echo -e "${GREEN}Бинарный файл успешно загружен через wget!${NC}"
        fi
    else
        echo -e "${GREEN}Бинарный файл уже присутствует в директории.${NC}"
    fi
    
    # Распаковка архива
    echo -e "${BLUE}Распаковываем архив...${NC}"
    tar -xzf /opt/popcache/pop-v0.3.0-linux-x64.tar.gz
    chmod +x /opt/popcache/pop
    
    # Проверка бинарного файла
    echo -e "${BLUE}Проверяем бинарный файл...${NC}"
    /opt/popcache/pop --help
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ошибка в бинарном файле pop. Проверьте, что файл распакован корректно.${NC}"
        return 1
    fi
    
    # 5. Настройка конфигурационного файла
    echo -e "${BLUE}5. Настраиваем конфигурационный файл...${NC}"
    read -p "Введите имя вашей POP-ноды: " pop_name
    
    # Автоматическое определение местоположения
    echo -e "${BLUE}Определяем местоположение сервера...${NC}"
    
    # Устанавливаем jq, если не установлен
    if ! command -v jq &> /dev/null; then
        apt install -y jq
    fi
    
    # Автоматическое определение местоположения через IP
    auto_location=$(curl -s https://ipinfo.io/json | jq -r '.region + ", " + .country')
    echo -e "${GREEN}🌍 Автоматически определенное местоположение: $auto_location${NC}"
    
    read -p "Использовать автоматически определённое местоположение? (y/n): " use_auto_location
    
    if [[ $use_auto_location == "y" || $use_auto_location == "Y" ]]; then
        pop_location="$auto_location"
    else
        read -p "Введите местоположение ноды (город, страна): " pop_location
    fi
    read -p "Введите пригласительный код: " invite_code
    read -p "Введите имя ноды (для идентификации): " node_name
    read -p "Введите ваше имя: " user_name
    read -p "Введите ваш email: " user_email
    read -p "Введите ваш веб-сайт (или GitHub): " user_website
    read -p "Введите ваш Discord username: " user_discord
    read -p "Введите ваш Telegram username: " user_telegram
    read -p "Введите адрес вашего Solana кошелька для наград: " solana_pubkey
    
    # Настройка параметров кэширования
    read -p "Введите размер кэша в оперативной памяти (МБ, рекомендуется 4096): " memory_cache_size
    memory_cache_size=${memory_cache_size:-4096}
    
    read -p "Введите размер дискового кэша (ГБ, рекомендуется 100): " disk_cache_size
    disk_cache_size=${disk_cache_size:-100}
    
    # Создаем конфигурационный файл
    cat > /opt/popcache/config.json << EOL
{
  "pop_name": "$pop_name",
  "pop_location": "$pop_location",
  "invite_code": "$invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": 0
  },
  "cache_config": {
    "memory_cache_size_mb": $memory_cache_size,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $disk_cache_size,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$node_name",
    "name": "$user_name",
    "email": "$user_email",
    "website": "$user_website",
    "discord": "$user_discord",
    "telegram": "$user_telegram",
    "solana_pubkey": "$solana_pubkey"
  }
}
EOL

    echo -e "${GREEN}Конфигурационный файл создан.${NC}"
    
    # 6. Создание systemd-службы
    echo -e "${BLUE}6. Создаем systemd-службу...${NC}"
    cat > /etc/systemd/system/popcache.service << EOL
[Unit]
Description=POP Cache Node
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/popcache
ExecStart=/opt/popcache/pop
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:/opt/popcache/logs/stdout.log
StandardError=append:/opt/popcache/logs/stderr.log
Environment=POP_CONFIG_PATH=/opt/popcache/config.json

[Install]
WantedBy=multi-user.target
EOL
    
    # Установка утилит для проверки портов
    apt install -y lsof net-tools psmisc

    # Проверка и освобождение портов перед запуском
    echo -e "${BLUE}7. Проверка и освобождение портов...${NC}"
    for PORT in 80 443; do
        if lsof -i :$PORT &>/dev/null; then
            echo -e "${YELLOW}⚠️ Порт $PORT занят. Освобождаем порт...${NC}"
            fuser -k ${PORT}/tcp || true
            sleep 2
        else
            echo -e "${GREEN}✅ Порт $PORT свободен.${NC}"
        fi
    done

    # Перезагрузка systemd и запуск службы
    echo -e "${BLUE}8. Запускаем службу...${NC}"
    systemctl daemon-reload
    systemctl enable popcache
    systemctl start popcache
    
    # Проверка статуса
    echo -e "${BLUE}9. Проверяем статус ноды...${NC}"
    sleep 5
    systemctl status popcache
    
    # Проверка логов и диагностика портов
    if ! systemctl is-active --quiet popcache; then
        echo -e "${RED}Служба не запустилась. Проверим логи:${NC}"
        journalctl -u popcache --no-pager -n 50
    else
        # Даже если сервис запустился, проверим наличие ошибок с портами
        if grep -q "Address already in use" /opt/popcache/logs/stderr.log 2>/dev/null; then
            echo -e "${YELLOW}Обнаружены ошибки с портами в логах. Пробуем решить...${NC}"
            
            # Проверим, какие порты заняты
            echo -e "${BLUE}Проверка занятых портов:${NC}"
            ss -tulpn | grep -E ':80|:443'
            
            echo -e "${YELLOW}Несмотря на ошибки портов, нода может работать нормально.${NC}"
            echo -e "${BLUE}Проверим регистрацию ноды:${NC}"
            
            # Проверка регистрации ноды
            if grep -q "Extracted pop_id" /opt/popcache/logs/stdout.log 2>/dev/null; then
                POP_ID=$(grep "Extracted pop_id" /opt/popcache/logs/stdout.log | tail -1 | sed 's/.*Extracted pop_id: \([0-9]*\).*/\1/')
                echo -e "${GREEN}Нода успешно зарегистрирована в сети Pipe Network!${NC}"
                echo -e "${BLUE}ID ноды (pop_id): ${YELLOW}$POP_ID${NC}"
            else
                echo -e "${RED}Нода не зарегистрирована в сети Pipe Network.${NC}"
                echo -e "${YELLOW}Проверьте логи для выяснения причины.${NC}"
            fi
            
            # Предлагаем решение для портов
            echo -e "${BLUE}Рекомендация:${NC} Если вы хотите избежать ошибок с портами, измените в config.json порты 80 и 443 на нестандартные (например, 8080 и 8443).${NC}"
        else
            echo -e "${GREEN}Нода Pipe Network Testnet успешно установлена и запущена!${NC}"
            
            # Проверка доступности API-эндпоинтов
            SERVER_IP=$(hostname -I | awk '{print $1}')
            echo -e "${BLUE}Проверка доступности эндпоинтов API:${NC}"
            echo -e "${YELLOW}Здоровье: curl -sk http://$SERVER_IP/health${NC}"
            echo -e "${YELLOW}Статус: curl -sk http://$SERVER_IP/state${NC}"
            echo -e "${YELLOW}Метрики: curl -sk http://$SERVER_IP/metrics${NC}"
            
            # Проверка регистрации ноды
            if grep -q "Extracted pop_id" /opt/popcache/logs/stdout.log 2>/dev/null; then
                POP_ID=$(grep "Extracted pop_id" /opt/popcache/logs/stdout.log | tail -1 | sed 's/.*Extracted pop_id: \([0-9]*\).*/\1/')
                echo -e "${GREEN}Нода успешно зарегистрирована в сети Pipe Network!${NC}"
                echo -e "${BLUE}ID ноды (pop_id): ${YELLOW}$POP_ID${NC}"
            fi
        fi
    fi
    
    echo -e "${BLUE}Вы можете проверить статус ноды в любое время:${NC}"
    echo -e "${YELLOW}Статус службы:  systemctl status popcache${NC}"
    echo -e "${YELLOW}Просмотр логов: journalctl -u popcache -f${NC}"
    echo -e "${YELLOW}Просмотр занятых портов: ss -tulpn | grep -E ':80|:443'${NC}"
    
    # Создаем резервную копию данных ноды
    mkdir -p "$BACKUP_DIR"
    cp -f "/opt/popcache/config.json" "$BACKUP_DIR/config_backup_$(date +%Y%m%d_%H%M%S).json"
    log_message "${GREEN}Резервная копия конфигурации создана в $BACKUP_DIR${NC}"
    
    read -p "Нажмите любую клавишу для возврата в меню..." -n1 -s
}

# Функция мониторинга ноды
monitor_node() {
    while true; do
        clear
        echo -e "${BLUE}=== Мониторинг ноды ===${NC}"
        echo "1. Показать статус сервиса"
        echo "2. Просмотр логов в реальном времени"
        echo "3. Проверить регистрацию ноды"
        echo "4. Проверить использование диска"
        echo "5. Проверить порты 80 и 443"
        echo "6. Проверить работу ноды (health check)"
        echo "7. Показать полную информацию о сетевых подключениях"
        echo "0. Вернуться в главное меню"
        echo
        read -r subchoice

        case $subchoice in
            1)
                echo -e "${BLUE}Статус сервиса:${NC}"
                systemctl status popcache.service
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            2)
                echo -e "${BLUE}Логи в реальном времени (нажмите Ctrl+C для возврата в меню):${NC}"
                # Сохраняем текущий обработчик прерывания
                trap_save=$(trap -p INT)
                
                # Устанавливаем пустой обработчик прерывания, чтобы Ctrl+C не завершал скрипт
                trap "" INT
                
                # Запускаем journalctl в контролируемом режиме
                journalctl -fu popcache.service || true
                
                # Восстанавливаем исходный обработчик прерывания
                if [ -n "$trap_save" ]; then
                    eval "$trap_save"
                else
                    trap - INT
                fi
                
                echo -e "\n${GREEN}Возвращение в меню мониторинга...${NC}"
                sleep 1
                ;;
            3)
                # Проверяем регистрацию ноды путем анализа логов
                echo -e "${BLUE}Проверяем регистрацию ноды...${NC}"
                if grep -q "Successfully registered" /opt/popcache/logs/stdout.log 2>/dev/null; then
                    echo -e "${GREEN}Нода успешно зарегистрирована!${NC}"
                elif grep -q "Node already registered" /opt/popcache/logs/stdout.log 2>/dev/null; then
                    echo -e "${GREEN}Нода уже зарегистрирована и активна.${NC}"
                else
                    echo -e "${YELLOW}Статус регистрации ноды неясен. Проверьте полные логи.${NC}"
                fi
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            4)
                echo -e "${BLUE}Использование диска:${NC}"
                df -h /opt/popcache
                echo -e "\n${BLUE}Размер директории кэша:${NC}"
                du -sh /opt/popcache/cache 2>/dev/null || echo "Директория кэша не найдена или пуста"
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            5)
                echo -e "${BLUE}Проверка портов 80 и 443:${NC}"
                echo -e "${YELLOW}Проверяем, что порты 80 и 443 заняты нодой...${NC}"
                ss -tulnp | grep -E ':80|:443'
                echo -e "\n${BLUE}Подробная информация о порте 80:${NC}"
                lsof -i :80
                echo -e "\n${BLUE}Подробная информация о порте 443:${NC}"
                lsof -i :443
                echo -e "${GREEN}Порты 80 и 443 должны быть заняты вашей нодой.${NC}"
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            6)
                echo -e "${BLUE}Проверка работоспособности ноды (health check):${NC}"
                response=$(curl -s http://localhost/health 2>/dev/null)
                if [ -z "$response" ]; then
                    echo -e "${RED}Нода не отвечает на health check.${NC}"
                elif [[ "$response" == *"\"status\":\"ok\""* ]]; then
                    echo -e "${GREEN}Нода работает корректно! Ответ: $response${NC}"
                    echo -e "${GREEN}Ваша нода работает и отвечает. Оставьте её запущенной на 24 часа для накопления нагрузки.${NC}"
                else
                    echo -e "${YELLOW}Нода отвечает, но статус не 'ok'. Ответ: $response${NC}"
                fi
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            7)
                echo -e "${BLUE}Полная информация о сетевых подключениях:${NC}"
                lsof -i
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}Неверный выбор${NC}"
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
        esac
    done
}

# Функция удаления ноды
remove_node() {
    echo -e "${RED}Вы уверены, что хотите удалить ноду Pipe Network Testnet? (y/n)${NC}"
    read -r confirm
    if [ "$confirm" = "y" ]; then
        echo -e "${YELLOW}Хотите сделать резервную копию данных ноды перед удалением? (y/n)${NC}"
        read -r backup_confirm
        
        if [ "$backup_confirm" = "y" ]; then
            backup_node_data
        fi
        
        systemctl stop popcache.service
        systemctl disable popcache.service
        rm /etc/systemd/system/popcache.service
        systemctl daemon-reload
        
        echo -e "${YELLOW}Хотите удалить все данные ноды, включая кэш? (y/n)${NC}"
        read -r data_confirm
        if [ "$data_confirm" = "y" ]; then
            rm -rf /opt/popcache
            echo -e "${GREEN}Все данные ноды удалены${NC}"
        else
            echo -e "${GREEN}Сервис ноды удален, но данные сохранены в /opt/popcache${NC}"
        fi
    fi
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция резервного копирования данных ноды
backup_node_data() {
    echo -e "${BLUE}=== Создание резервной копии данных ноды ===${NC}"
    
    # Создаем директорию для резервных копий, если она не существует
    mkdir -p "$BACKUP_DIR"
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_file="$BACKUP_DIR/pipe_node_backup_$timestamp.tar.gz"
    
    if [ -f "/opt/popcache/config.json" ]; then
        # Резервное копирование только важных файлов, без кэша
        echo -e "${BLUE}Создаем архив резервной копии...${NC}"
        
        # Проверяем наличие критически важного файла .pop_state.json
        if [ -f "/opt/popcache/.pop_state.json" ]; then
            echo -e "${GREEN}Обнаружен файл .pop_state.json - приватный идентификатор узла!${NC}"
            # Архивируем все критически важные файлы, включая скрытый файл .pop_state.json
            cd /opt/popcache && tar -czf "$backup_file" config.json .pop_state.json logs 2>/dev/null
            echo -e "${YELLOW}ВАЖНО: Файл .pop_state.json включен в резервную копию. Без него восстановление узла невозможно!${NC}"
        else
            echo -e "${YELLOW}Файл .pop_state.json не найден! Без него восстановление ноды будет невозможно.${NC}"
            # Создаем резервную копию без .pop_state.json 
            tar -czf "$backup_file" -C /opt/popcache config.json logs 2>/dev/null
        fi
        
        if [ -f "$backup_file" ]; then
            echo -e "${GREEN}Резервная копия успешно создана в:${NC} $backup_file"
            
            # Экспортируем важную информацию в текстовый файл для легкой настройки на другом сервере
            echo -e "${BLUE}Извлекаем важную информацию для миграции...${NC}"
            migration_file="$BACKUP_DIR/migration_info_$timestamp.txt"
            
            echo "=== Информация для миграции ноды Pipe Network Testnet ===" > "$migration_file"
            echo "Дата резервного копирования: $(date)" >> "$migration_file"
            echo "\nИнформация конфигурации:" >> "$migration_file"
            
            # Извлекаем ключевую информацию из config.json
            if command -v jq &> /dev/null; then
                echo "Имя POP: $(jq -r '.pop_name // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Местоположение POP: $(jq -r '.pop_location // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Пригласительный код: $(jq -r '.invite_code // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Имя ноды: $(jq -r '.identity_config.node_name // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Имя: $(jq -r '.identity_config.name // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Email: $(jq -r '.identity_config.email // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Веб-сайт: $(jq -r '.identity_config.website // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Discord: $(jq -r '.identity_config.discord // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Telegram: $(jq -r '.identity_config.telegram // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Solana ключ: $(jq -r '.identity_config.solana_pubkey // "Не найдено"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Размер кэша в памяти (МБ): $(jq -r '.cache_config.memory_cache_size_mb // "4096"' /opt/popcache/config.json)" >> "$migration_file"
                echo "Размер дискового кэша (ГБ): $(jq -r '.cache_config.disk_cache_size_gb // "100"' /opt/popcache/config.json)" >> "$migration_file"
            else
                echo "jq не установлен, невозможно извлечь детали конфигурации" >> "$migration_file"
                # вместо этого копируем весь файл конфигурации
                echo "\nРав config.json:" >> "$migration_file"
                cat /opt/popcache/config.json >> "$migration_file"
            fi
            
            # Добавляем инструкции по миграции
            echo "\n\n=== ИНСТРУКЦИЯ ПО МИГРАЦИИ ===" >> "$migration_file"
            echo "1. Перенесите файлы config.json и .pop_state.json на новый сервер в директорию /opt/popcache" >> "$migration_file"
            echo "2. ПРИ ПЕРЕНОСЕ НА ДРУГОЙ СЕРВЕР ОБЯЗАТЕЛЬНО ИЗМЕНИТЕ МЕСТОПОЛОЖЕНИЕ В ФАЙЛЕ config.json!" >> "$migration_file"
            echo "3. Для определения нового местоположения используйте команду: curl -s https://ipinfo.io/json | jq -r '.region + ", " + .country'" >> "$migration_file"
            echo "4. Измените значение pop_location в config.json на новое местоположение" >> "$migration_file"
            echo "5. Создайте systemd службу и запустите ноду" >> "$migration_file"
            
            echo -e "${GREEN}Информация для миграции сохранена в:${NC} $migration_file"
            echo -e "${YELLOW}ВАЖНО: Храните эту информацию в безопасности для настройки на новом сервере${NC}"
            echo -e "${RED}ПРИ ПЕРЕНОСЕ НА ДРУГОЙ СЕРВЕР ОБЯЗАТЕЛЬНО ИЗМЕНИТЕ МЕСТОПОЛОЖЕНИЕ В ФАЙЛЕ config.json!${NC}"
            
            # Запрашиваем, хочет ли пользователь создать веб-ссылку для скачивания
            echo -e "\n${BLUE}Создать временную ссылку для скачивания резервной копии?${NC}"
            read -p "Создать временную ссылку? (y/n): " create_temp_link
            
            if [[ $create_temp_link == "y" || $create_temp_link == "Y" ]]; then
                # Устанавливаем python если не установлен
                if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
                    apt update && apt install -y python3
                fi
                
                # Определяем команду Python
                if command -v python3 &> /dev/null; then
                    PY_CMD="python3"
                else
                    PY_CMD="python"
                fi
                
                # Создаем временную директорию для веб-сервера
                tmp_dir="/tmp/pipe_backup_download"
                mkdir -p "$tmp_dir"
                cp "$backup_file" "$tmp_dir/"
                cp "$migration_file" "$tmp_dir/"
                
                # Создаем HTML страницу с кнопками для скачивания
                cat > "$tmp_dir/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Pipe Network Бэкап Ноды</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        h1 {
            color: #0066cc;
            text-align: center;
        }
        .container {
            background-color: white;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .button {
            display: inline-block;
            background-color: #4CAF50;
            color: white;
            padding: 10px 20px;
            text-align: center;
            text-decoration: none;
            font-size: 16px;
            margin: 10px 5px;
            cursor: pointer;
            border-radius: 4px;
            border: none;
        }
        .warning {
            color: red;
            font-weight: bold;
            text-align: center;
            margin: 20px 0;
        }
        .countdown {
            text-align: center;
            font-size: 18px;
            font-weight: bold;
            margin: 20px 0;
        }
        .file-info {
            margin-bottom: 15px;
            padding: 10px;
            background-color: #f9f9f9;
            border-left: 3px solid #0066cc;
        }
    </style>
</head>
<body>
    <h1>Pipe Network Бэкап Ноды</h1>
    
    <div class="container">
        <h2>Файлы для скачивания:</h2>
        
        <div class="file-info">
            <h3>Архив бэкапа</h3>
            <p>Содержит все необходимые файлы для восстановления ноды, включая config.json и .pop_state.json.</p>
            <a class="button" href="./$(basename "$backup_file")" download>Скачать Архив Бэкапа</a>
        </div>
        
        <div class="file-info">
            <h3>Инструкция по миграции</h3>
            <p>Текстовый файл с подробными инструкциями по восстановлению ноды на новом сервере.</p>
            <a class="button" href="./$(basename "$migration_file")" download>Скачать Инструкцию</a>
        </div>
    </div>
    
    <div class="warning">ВНИМАНИЕ! Эта страница будет доступна только 3 минуты!</div>
    
    <div class="countdown" id="countdown">Осталось времени: 10:00</div>
    
    <script>
        // Функция обратного отсчета
        var timeLeft = 3 * 60; // 3 минуты в секундах
        var countdownEl = document.getElementById('countdown');
        
        function updateCountdown() {
            var minutes = Math.floor(timeLeft / 60);
            var seconds = timeLeft % 60;
            countdownEl.innerHTML = 'Осталось времени: ' + minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
            
            if (timeLeft <= 0) {
                countdownEl.innerHTML = 'Время истекло!';
            } else {
                timeLeft--;
                setTimeout(updateCountdown, 1000);
            }
        }
        
        updateCountdown();
    </script>
</body>
</html>
EOF
                
                # Запускаем простой HTTP сервер на порту 8000
                SERVER_IP=$(hostname -I | awk '{print $1}')
                PORT=8090
                
                # Проверяем, занят ли порт
                if netstat -tuln | grep -q ":$PORT "; then
                    echo -e "${YELLOW}Порт $PORT уже занят. Выбираем другой порт...${NC}"
                    # Выбираем другой порт из диапазона 8090-8099
                    for TEST_PORT in $(seq 8090 8099); do
                        if ! netstat -tuln | grep -q ":$TEST_PORT "; then
                            PORT=$TEST_PORT
                            echo -e "${GREEN}Выбран порт $PORT${NC}"
                            break
                        fi
                    done
                fi
                
                # Открываем порт в фаерволе, если он активен
                if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
                    ufw allow $PORT/tcp
                    echo -e "${BLUE}Порт $PORT открыт в фаерволе${NC}"
                fi
                
                # Переходим в директорию и запускаем сервер в фоне
                cd "$tmp_dir" && $PY_CMD -m http.server $PORT > "$tmp_dir/server.log" 2>&1 &
                HTTP_PID=$!
                
                # Проверяем, запустился ли сервер
                sleep 2
                if ! ps -p $HTTP_PID > /dev/null; then
                    echo -e "${RED}Ошибка запуска HTTP сервера. Проверьте логи: $tmp_dir/server.log${NC}"
                    cat "$tmp_dir/server.log"
                else
                    echo -e "${GREEN}HTTP сервер успешно запущен с PID: $HTTP_PID${NC}"
                fi
                
                # Создаем скрипт автоматического завершения через 10 минут
                cat > "$tmp_dir/cleanup.sh" << 'EOFSCRIPT'
#!/bin/bash
sleep 180  # Ждем 3 минуты
killall -9 python3 python 2>/dev/null || true
rm -rf /tmp/pipe_backup_download
EOFSCRIPT
                
                chmod +x "$tmp_dir/cleanup.sh"
                nohup "$tmp_dir/cleanup.sh" > /dev/null 2>&1 &
                
                echo -e "\n${GREEN}✅ Веб-страница для скачивания файлов создана!${NC}"
                echo -e "${BLUE}Откройте в браузере:${NC} ${YELLOW}http://$SERVER_IP:$PORT${NC}"
                echo -e "${GREEN}Будет открыта удобная страница с кнопками для скачивания файлов.${NC}"
                echo -e "${RED}ВНИМАНИЕ: Страница будет активна только 3 минуты!${NC}"
            fi
        else
            echo -e "${RED}Создание резервной копии не удалось${NC}"
        fi
    else
        echo -e "${RED}Конфигурация ноды не найдена в /opt/popcache/config.json${NC}"
    fi
    
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция восстановления данных ноды
restore_node_data() {
    echo -e "${BLUE}=== Восстановление данных ноды ===${NC}"
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -e "${RED}Резервные копии не найдены в $BACKUP_DIR${NC}"
        echo -e "${YELLOW}Хотите использовать файл миграции для настройки ноды? (y/n)${NC}"
        read -r migration_confirm
        
        if [ "$migration_confirm" = "y" ]; then
            echo -e "${BLUE}Введите полный путь к вашему файлу информации о миграции:${NC}"
            read -r migration_file
            
            if [ -f "$migration_file" ]; then
                echo -e "${GREEN}Файл миграции найден. Используем его для настройки ноды.${NC}"
                echo -e "${YELLOW}Это запустит установку ноды со значениями из файла миграции.${NC}"
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                
                # Вызов функции установки с данными миграции
                # Это должно быть реализовано для анализа файла миграции
                # и использования его значений для установки
                # Пока мы просто вызываем обычную установку
                install_testnet_node
            else
                echo -e "${RED}Файл миграции не найден по пути $migration_file${NC}"
            fi
        fi
    else
        # Показываем доступные резервные копии
        echo -e "${BLUE}Доступные резервные копии:${NC}"
        ls -1t "$BACKUP_DIR" | grep -E "\.tar\.gz$" | nl
        echo
        echo -e "${BLUE}Введите номер резервной копии для восстановления (или 0 для отмены):${NC}"
        read -r backup_number
        
        if [ "$backup_number" -gt 0 ] 2>/dev/null; then
            backup_file=$(ls -1t "$BACKUP_DIR" | grep -E "\.tar\.gz$" | sed -n "${backup_number}p")
            
            if [ -n "$backup_file" ]; then
                full_backup_path="$BACKUP_DIR/$backup_file"
                
                echo -e "${YELLOW}Это остановит текущий сервис ноды, если он запущен. Продолжить? (y/n)${NC}"
                read -r restore_confirm
                
                if [ "$restore_confirm" = "y" ]; then
                    # Останавливаем сервис, если он запущен
                    if systemctl is-active --quiet popcache.service; then
                        echo -e "${BLUE}Останавливаем сервис popcache...${NC}"
                        systemctl stop popcache.service
                    fi
                    
                    # Убеждаемся, что директория существует
                    mkdir -p /opt/popcache
                    
                    # Распаковываем резервную копию
                    echo -e "${BLUE}Восстанавливаем из резервной копии: $full_backup_path${NC}"
                    tar -xzf "$full_backup_path" -C /opt/popcache
                    
                    if [ -f "/opt/popcache/config.json" ]; then
                        echo -e "${GREEN}Конфигурация успешно восстановлена${NC}"
                        
                        # Убеждаемся, что системный сервис настроен правильно
                        echo -e "${BLUE}Проверяем правильность настройки системного сервиса...${NC}"
                        bash -c 'cat > /etc/systemd/system/popcache.service << EOL
[Unit]
Description=POP Cache Node
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/popcache
ExecStart=/opt/popcache/pop
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:/opt/popcache/logs/stdout.log
StandardError=append:/opt/popcache/logs/stderr.log
Environment=POP_CONFIG_PATH=/opt/popcache/config.json

[Install]
WantedBy=multi-user.target
EOL'
                        
                        # Проверяем наличие исполняемого файла
                        if [ ! -f "/opt/popcache/pop" ]; then
                            echo -e "${YELLOW}Исполняемый файл не найден. Скачиваем...${NC}"
                            cd /opt/popcache
                            wget https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz
                            tar -xzf pop-v0.3.0-linux-*.tar.gz
                            chmod 755 /opt/popcache/pop
                        fi
                        
                        # Запускаем сервис
                        echo -e "${BLUE}Запускаем сервис...${NC}"
                        systemctl daemon-reload
                        systemctl enable popcache.service
                        systemctl start popcache.service
                        
                        if systemctl is-active --quiet popcache.service; then
                            echo -e "${GREEN}Нода Pipe Network Testnet восстановлена и запущена!${NC}"
                        else
                            echo -e "${RED}Не удалось запустить сервис. Проверьте логи с помощью 'journalctl -u popcache.service'${NC}"
                        fi
                    else
                        echo -e "${RED}Восстановление не удалось - config.json не найден после распаковки${NC}"
                    fi
                fi
            else
                echo -e "${RED}Неверный выбор резервной копии${NC}"
            fi
        elif [ "$backup_number" -ne 0 ]; then
            echo -e "${RED}Неверный выбор${NC}"
        fi
    fi
    
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция диагностики проблем запуска ноды
diagnose_node_issues() {
    echo -e "${BLUE}=== Диагностика проблем запуска ноды ===${NC}"
    
    # Директория для сохранения результатов диагностики
    DIAG_DIR="/root/pipe_diagnostics"
    mkdir -p "$DIAG_DIR"
    DIAG_FILE="$DIAG_DIR/diagnostics_$(date +%Y%m%d_%H%M%S).txt"
    
    echo -e "${YELLOW}Проверяем статус сервиса...${NC}" | tee -a "$DIAG_FILE"
    systemctl status popcache.service -l | tee -a "$DIAG_FILE"
    
    echo -e "\n${YELLOW}Анализируем последние ошибки в логах...${NC}" | tee -a "$DIAG_FILE"
    journalctl -u popcache.service -n 50 --no-pager | tee -a "$DIAG_FILE"
    
    echo -e "\n${YELLOW}Проверяем наличие необходимых файлов...${NC}" | tee -a "$DIAG_FILE"
    ls -la /opt/popcache/ | tee -a "$DIAG_FILE"
    
    echo -e "\n${YELLOW}Проверяем конфигурацию...${NC}" | tee -a "$DIAG_FILE"
    if [ -f "/opt/popcache/config.json" ]; then
        echo -e "${GREEN}Файл конфигурации найден${NC}" | tee -a "$DIAG_FILE"
        if command -v jq &> /dev/null; then
            if jq . /opt/popcache/config.json > /dev/null 2>&1; then
                echo -e "${GREEN}JSON формат корректный${NC}" | tee -a "$DIAG_FILE"
                jq . /opt/popcache/config.json | tee -a "$DIAG_FILE"
            else
                echo -e "${RED}Ошибка в формате JSON!${NC}" | tee -a "$DIAG_FILE"
            fi
        else
            echo -e "${YELLOW}jq не установлен, невозможно проверить JSON${NC}" | tee -a "$DIAG_FILE"
        fi
    else
        echo -e "${RED}Файл конфигурации не найден!${NC}" | tee -a "$DIAG_FILE"
    fi
    
    echo -e "\n${YELLOW}Проверяем исполняемый файл...${NC}" | tee -a "$DIAG_FILE"
    if [ -f "/opt/popcache/pop" ]; then
        echo -e "${GREEN}Исполняемый файл найден${NC}" | tee -a "$DIAG_FILE"
        if [ -x "/opt/popcache/pop" ]; then
            echo -e "${GREEN}Файл имеет права на исполнение${NC}" | tee -a "$DIAG_FILE"
        else
            echo -e "${RED}Файл НЕ имеет прав на исполнение!${NC}" | tee -a "$DIAG_FILE"
            echo -e "${YELLOW}Хотите установить права на исполнение? (y/n)${NC}"
            read -r fix_perms
            if [ "$fix_perms" = "y" ]; then
                chmod +x /opt/popcache/pop
                echo -e "${GREEN}Права исправлены${NC}" | tee -a "$DIAG_FILE"
            fi
        fi
    else
        echo -e "${RED}Исполняемый файл не найден!${NC}" | tee -a "$DIAG_FILE"
    fi
    
    echo -e "\n${YELLOW}Проверяем использование дискового пространства...${NC}" | tee -a "$DIAG_FILE"
    df -h | tee -a "$DIAG_FILE"
    
    echo -e "\n${YELLOW}Проверяем использование памяти...${NC}" | tee -a "$DIAG_FILE"
    free -h | tee -a "$DIAG_FILE"
    
    echo -e "\n${YELLOW}Проверяем сетевые порты...${NC}" | tee -a "$DIAG_FILE"
    netstat -tulpn | grep -E ':(80|443)' | tee -a "$DIAG_FILE"
    
    echo -e "\n${BLUE}==== Возможные решения: ====${NC}" | tee -a "$DIAG_FILE"
    echo -e "1. Перезапустить службу: ${GREEN}sudo systemctl restart popcache.service${NC}" | tee -a "$DIAG_FILE"
    echo -e "2. Убедиться, что порты 80 и 443 свободны: ${GREEN}sudo netstat -tulpn | grep -E ':(80|443)'${NC}" | tee -a "$DIAG_FILE"
    echo -e "3. Исправить права доступа: ${GREEN}sudo chmod +x /opt/popcache/pop${NC}" | tee -a "$DIAG_FILE"
    echo -e "4. Убедиться, что config.json корректный: ${GREEN}sudo jq . /opt/popcache/config.json${NC}" | tee -a "$DIAG_FILE"
    
    echo -e "\n${GREEN}Диагностика завершена. Полный отчет сохранен в файле:${NC} $DIAG_FILE"
    echo -e "${YELLOW}Для просмотра полного отчета используйте:${NC} cat $DIAG_FILE"
    
    echo -e "\n${YELLOW}Хотите перезапустить службу? (y/n)${NC}"
    read -r restart_service
    if [ "$restart_service" = "y" ]; then
        systemctl restart popcache.service
        sleep 2
        systemctl status popcache.service
    fi
    echo -e "\n${YELLOW}Проверяем оперативную память...${NC}" | tee -a "$DIAG_FILE"
    free -h | tee -a "$DIAG_FILE"
    
    # Проверяем порты
    echo -e "\n${YELLOW}Проверяем занятые порты:${NC}" | tee -a "$DIAG_FILE"
    netstat -tulpn | grep -E ':(80|443)' | tee -a "$DIAG_FILE"
    
    # Предлагаем решения
    echo -e "\n${BLUE}==== Возможные решения проблемы: ====${NC}" | tee -a "$DIAG_FILE"
    echo -e "1. Перезапустить службу: sudo systemctl restart popcache.service" | tee -a "$DIAG_FILE"
    echo -e "2. Проверить права доступа: sudo chmod +x /opt/popcache/pop" | tee -a "$DIAG_FILE"
    echo -e "3. Убедиться, что порты 80 и 443 свободны" | tee -a "$DIAG_FILE"
    echo -e "4. Переустановить ноду (пункт 1 в главном меню)" | tee -a "$DIAG_FILE"
    
    # Предлагаем исправить права доступа
    echo -e "\n${YELLOW}Хотите исправить права доступа к файлам? (y/n)${NC}"
    read -r fix_perms
    if [ "$fix_perms" = "y" ]; then
        echo -e "${GREEN}Исправляем права...${NC}"
        chmod +x /opt/popcache/pop
        chown -R root:root /opt/popcache
        chmod -R 755 /opt/popcache
        echo -e "${GREEN}Права исправлены.${NC}"
        
        echo -e "${YELLOW}Перезапустить службу? (y/n)${NC}"
        read -r restart_service
        if [ "$restart_service" = "y" ]; then
            systemctl restart popcache.service
            sleep 2
            systemctl status popcache.service
        fi
    fi
    
    # Сохраняем отчет и выводим путь к нему
    echo -e "\n${GREEN}Диагностика завершена. Полный отчет сохранен в файле:${NC}"
    echo "$DIAG_FILE"
    
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Основной цикл меню
while true; do
    show_menu
    read -r choice
    case $choice in
        1) install_testnet_node ;;
        2) monitor_node ;;
        3) remove_node ;;
        4) backup_node_data ;;
        5) restore_node_data ;;
        6) show_logs ;;
        7) diagnose_node_issues ;;
        8) stop_devnet_node ;;
        0) exit 0 ;;
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac
done
# Функция для установки через Docker
install_docker_node() {
    log_message "${GREEN}Начинаем установку ноды Pipe Network Testnet через Docker...${NC}"
    
    # Проверяем установлен ли Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker не установлен. Устанавливаем Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi

    # Создаем директорию для конфигурации
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # Запрашиваем информацию у пользователя
    echo -e "${BLUE}Теперь создадим конфигурационный файл с вашей информацией${NC}"
    echo
    read -p "Введите ваше имя POP: " pop_name
    read -p "Введите ваш город и страну (например, Москва, Россия): " pop_location
    read -p "Введите ваш пригласительный код из письма: " invite_code
    read -p "Введите имя вашей ноды: " node_name
    read -p "Введите ваше полное имя: " full_name
    read -p "Введите ваш адрес электронной почты: " email
    read -p "Введите ваш веб-сайт (или нажмите Enter для пропуска): " website
    read -p "Введите ваше имя пользователя Discord (или нажмите Enter для пропуска): " discord
    read -p "Введите ваш ник Telegram (или нажмите Enter для пропуска): " telegram
    read -p "Введите ваш публичный ключ Solana (адрес кошелька): " solana_pubkey
    
    # Запрашиваем параметры кэширования
    echo -e "${BLUE}Сколько памяти вы хотите выделить для кэша? (в МБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: 4096 для серверов с 8ГБ+ ОЗУ, 2048 для меньших серверов${NC}"
    read -p "Введите размер памяти (по умолчанию: 4096): " memory_cache_size
    memory_cache_size=${memory_cache_size:-4096}
    
    echo -e "${BLUE}Сколько дискового пространства вы хотите выделить для кэша? (в ГБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: минимум 100ГБ${NC}"
    read -p "Введите размер дискового кэша в ГБ (по умолчанию: 100): " disk_cache_size
    disk_cache_size=${disk_cache_size:-100}
    
    # Создаем конфигурационный файл
    echo -e "${GREEN}Создаем конфигурационный файл...${NC}"
    cat > "$DOCKER_CONFIG_DIR/config.json" << EOL
{
  "pop_name": "$pop_name",
  "pop_location": "$pop_location",
  "invite_code": "$invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": 40
  },
  "cache_config": {
    "memory_cache_size_mb": $memory_cache_size,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $disk_cache_size,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$node_name",
    "name": "$full_name",
    "email": "$email",
    "website": "$website",
    "discord": "$discord",
    "telegram": "$telegram",
    "solana_pubkey": "$solana_pubkey"
  }
}
EOL

    # Создаем Docker volume для данных кэша
    echo -e "${GREEN}Создаем Docker volume для данных...${NC}"
    docker volume create "$DOCKER_VOLUME_NAME"
    
    # Останавливаем существующий контейнер, если такой есть
    if docker ps -a | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${YELLOW}Останавливаем существующий контейнер...${NC}"
        docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
        docker rm "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # Открываем порты в фаерволе
    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}Открываем порты в фаерволе...${NC}"
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    
    # Запускаем контейнер Docker
    echo -e "${GREEN}Запускаем контейнер Docker с нодой Pipe Network...${NC}"
    docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        --restart always \
        -p 80:80 \
        -p 443:443 \
        -v "$DOCKER_CONFIG_DIR/config.json:/opt/popcache/config.json" \
        -v "$DOCKER_VOLUME_NAME:/opt/popcache/cache" \
        -e POP_CONFIG_PATH=/opt/popcache/config.json \
        --pull always \
        ubuntu:24.04 /bin/bash -c \
        "apt-get update && \
         apt-get install -y curl wget tar && \
         mkdir -p /opt/popcache/logs && \
         cd /opt/popcache && \
         wget https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz && \
         tar -xzf pop-v0.3.0-linux-*.tar.gz && \
         chmod 755 /opt/popcache/pop && \
         /opt/popcache/pop"
    
    # Проверяем, запустился ли контейнер успешно
    sleep 5
    if docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${GREEN}Контейнер успешно запущен!${NC}"
        echo -e "${BLUE}Проверьте работу ноды:${NC}"
        echo -e "${YELLOW}Состояние: http://$(hostname -I | awk '{print $1}')/state${NC}"
        echo -e "${YELLOW}Проверка здоровья: http://$(hostname -I | awk '{print $1}')/health${NC}"
        echo -e "${GREEN}Нода Pipe Network Testnet успешно установлена через Docker!${NC}"
    else
        echo -e "${RED}Возникла проблема при запуске контейнера Docker.${NC}"
        echo -e "${YELLOW}Проверьте логи контейнера: docker logs $DOCKER_CONTAINER_NAME${NC}"
    fi
    
    # Создаем резервную копию конфигурации
    mkdir -p "$BACKUP_DIR"
    cp -r "$DOCKER_CONFIG_DIR" "$BACKUP_DIR"
    echo -e "${BLUE}Конфигурация сохранена в $BACKUP_DIR${NC}"
    
    read -p "Нажмите любую клавишу для возврата в меню..." -n1 -s
    clear
}# Функция для установки через Docker
install_docker_node() {
    log_message "${GREEN}Начинаем установку ноды Pipe Network Testnet через Docker...${NC}"
    
    # Проверяем установлен ли Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker не установлен. Устанавливаем Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi

    # Создаем директорию для конфигурации
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # Запрашиваем информацию у пользователя
    echo -e "${BLUE}Теперь создадим конфигурационный файл с вашей информацией${NC}"
    echo
    read -p "Введите ваше имя POP: " pop_name
    read -p "Введите ваш город и страну (например, Москва, Россия): " pop_location
    read -p "Введите ваш пригласительный код из письма: " invite_code
    read -p "Введите имя вашей ноды: " node_name
    read -p "Введите ваше полное имя: " full_name
    read -p "Введите ваш адрес электронной почты: " email
    read -p "Введите ваш веб-сайт (или нажмите Enter для пропуска): " website
    read -p "Введите ваше имя пользователя Discord (или нажмите Enter для пропуска): " discord
    read -p "Введите ваш ник Telegram (или нажмите Enter для пропуска): " telegram
    read -p "Введите ваш публичный ключ Solana (адрес кошелька): " solana_pubkey
    
    # Запрашиваем параметры кэширования
    echo -e "${BLUE}Сколько памяти вы хотите выделить для кэша? (в МБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: 4096 для серверов с 8ГБ+ ОЗУ, 2048 для меньших серверов${NC}"
    read -p "Введите размер памяти (по умолчанию: 4096): " memory_cache_size
    memory_cache_size=${memory_cache_size:-4096}
    
    echo -e "${BLUE}Сколько дискового пространства вы хотите выделить для кэша? (в ГБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: минимум 100ГБ${NC}"
    read -p "Введите размер дискового кэша в ГБ (по умолчанию: 100): " disk_cache_size
    disk_cache_size=${disk_cache_size:-100}
    
    # Создаем конфигурационный файл
    echo -e "${GREEN}Создаем конфигурационный файл...${NC}"
    cat > "$DOCKER_CONFIG_DIR/config.json" << EOL
{
  "pop_name": "$pop_name",
  "pop_location": "$pop_location",
  "invite_code": "$invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": 40
  },
  "cache_config": {
    "memory_cache_size_mb": $memory_cache_size,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $disk_cache_size,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$node_name",
    "name": "$full_name",
    "email": "$email",
    "website": "$website",
    "discord": "$discord",
    "telegram": "$telegram",
    "solana_pubkey": "$solana_pubkey"
  }
}
EOL

    # Создаем Docker volume для данных кэша
    echo -e "${GREEN}Создаем Docker volume для данных...${NC}"
    docker volume create "$DOCKER_VOLUME_NAME"
    
    # Останавливаем существующий контейнер, если такой есть
    if docker ps -a | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${YELLOW}Останавливаем существующий контейнер...${NC}"
        docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
        docker rm "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # Открываем порты в фаерволе
    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}Открываем порты в фаерволе...${NC}"
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    
    # Запускаем контейнер Docker
    echo -e "${GREEN}Запускаем контейнер Docker с нодой Pipe Network...${NC}"
    docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        --restart always \
        -p 80:80 \
        -p 443:443 \
        -v "$DOCKER_CONFIG_DIR/config.json:/opt/popcache/config.json" \
        -v "$DOCKER_VOLUME_NAME:/opt/popcache/cache" \
        -e POP_CONFIG_PATH=/opt/popcache/config.json \
        --pull always \
        ubuntu:24.04 /bin/bash -c \
        "apt-get update && \
         apt-get install -y curl wget tar && \
         mkdir -p /opt/popcache/logs && \
         cd /opt/popcache && \
         wget https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz && \
         tar -xzf pop-v0.3.0-linux-*.tar.gz && \
         chmod 755 /opt/popcache/pop && \
         /opt/popcache/pop"
    
    # Проверяем, запустился ли контейнер успешно
    sleep 5
    if docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${GREEN}Контейнер успешно запущен!${NC}"
        echo -e "${BLUE}Проверьте работу ноды:${NC}"
        echo -e "${YELLOW}Состояние: http://$(hostname -I | awk '{print $1}')/state${NC}"
        echo -e "${YELLOW}Проверка здоровья: http://$(hostname -I | awk '{print $1}')/health${NC}"
        echo -e "${GREEN}Нода Pipe Network Testnet успешно установлена через Docker!${NC}"
    else
        echo -e "${RED}Возникла проблема при запуске контейнера Docker.${NC}"
        echo -e "${YELLOW}Проверьте логи контейнера: docker logs $DOCKER_CONTAINER_NAME${NC}"
    fi
    
    # Создаем резервную копию конфигурации
    mkdir -p "$BACKUP_DIR"
    cp -r "$DOCKER_CONFIG_DIR" "$BACKUP_DIR"
    echo -e "${BLUE}Конфигурация сохранена в $BACKUP_DIR${NC}"
    
    read -p "Нажмите любую клавишу для возврата в меню..." -n1 -s
    clear
}# Функция для установки через Docker
install_docker_node() {
    log_message "${GREEN}Начинаем установку ноды Pipe Network Testnet через Docker...${NC}"
    
    # Проверяем установлен ли Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker не установлен. Устанавливаем Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi

    # Создаем директорию для конфигурации
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # Запрашиваем информацию у пользователя
    echo -e "${BLUE}Теперь создадим конфигурационный файл с вашей информацией${NC}"
    echo
    read -p "Введите ваше имя POP: " pop_name
    read -p "Введите ваш город и страну (например, Москва, Россия): " pop_location
    read -p "Введите ваш пригласительный код из письма: " invite_code
    read -p "Введите имя вашей ноды: " node_name
    read -p "Введите ваше полное имя: " full_name
    read -p "Введите ваш адрес электронной почты: " email
    read -p "Введите ваш веб-сайт (или нажмите Enter для пропуска): " website
    read -p "Введите ваше имя пользователя Discord (или нажмите Enter для пропуска): " discord
    read -p "Введите ваш ник Telegram (или нажмите Enter для пропуска): " telegram
    read -p "Введите ваш публичный ключ Solana (адрес кошелька): " solana_pubkey
    
    # Запрашиваем параметры кэширования
    echo -e "${BLUE}Сколько памяти вы хотите выделить для кэша? (в МБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: 4096 для серверов с 8ГБ+ ОЗУ, 2048 для меньших серверов${NC}"
    read -p "Введите размер памяти (по умолчанию: 4096): " memory_cache_size
    memory_cache_size=${memory_cache_size:-4096}
    
    echo -e "${BLUE}Сколько дискового пространства вы хотите выделить для кэша? (в ГБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: минимум 100ГБ${NC}"
    read -p "Введите размер дискового кэша в ГБ (по умолчанию: 100): " disk_cache_size
    disk_cache_size=${disk_cache_size:-100}
    
    # Создаем конфигурационный файл
    echo -e "${GREEN}Создаем конфигурационный файл...${NC}"
    cat > "$DOCKER_CONFIG_DIR/config.json" << EOL
{
  "pop_name": "$pop_name",
  "pop_location": "$pop_location",
  "invite_code": "$invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": 40
  },
  "cache_config": {
    "memory_cache_size_mb": $memory_cache_size,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $disk_cache_size,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$node_name",
    "name": "$full_name",
    "email": "$email",
    "website": "$website",
    "discord": "$discord",
    "telegram": "$telegram",
    "solana_pubkey": "$solana_pubkey"
  }
}
EOL

    # Создаем Docker volume для данных кэша
    echo -e "${GREEN}Создаем Docker volume для данных...${NC}"
    docker volume create "$DOCKER_VOLUME_NAME"
    
    # Останавливаем существующий контейнер, если такой есть
    if docker ps -a | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${YELLOW}Останавливаем существующий контейнер...${NC}"
        docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
        docker rm "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # Открываем порты в фаерволе
    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}Открываем порты в фаерволе...${NC}"
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    
    # Запускаем контейнер Docker
    echo -e "${GREEN}Запускаем контейнер Docker с нодой Pipe Network...${NC}"
    docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        --restart always \
        -p 80:80 \
        -p 443:443 \
        -v "$DOCKER_CONFIG_DIR/config.json:/opt/popcache/config.json" \
        -v "$DOCKER_VOLUME_NAME:/opt/popcache/cache" \
        -e POP_CONFIG_PATH=/opt/popcache/config.json \
        --pull always \
        ubuntu:24.04 /bin/bash -c \
        "apt-get update && \
         apt-get install -y curl wget tar && \
         mkdir -p /opt/popcache/logs && \
         cd /opt/popcache && \
         wget https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz && \
         tar -xzf pop-v0.3.0-linux-*.tar.gz && \
         chmod 755 /opt/popcache/pop && \
         /opt/popcache/pop"
    
    # Проверяем, запустился ли контейнер успешно
    sleep 5
    if docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${GREEN}Контейнер успешно запущен!${NC}"
        echo -e "${BLUE}Проверьте работу ноды:${NC}"
        echo -e "${YELLOW}Состояние: http://$(hostname -I | awk '{print $1}')/state${NC}"
        echo -e "${YELLOW}Проверка здоровья: http://$(hostname -I | awk '{print $1}')/health${NC}"
        echo -e "${GREEN}Нода Pipe Network Testnet успешно установлена через Docker!${NC}"
    else
        echo -e "${RED}Возникла проблема при запуске контейнера Docker.${NC}"
        echo -e "${YELLOW}Проверьте логи контейнера: docker logs $DOCKER_CONTAINER_NAME${NC}"
    fi
    
    # Создаем резервную копию конфигурации
    mkdir -p "$BACKUP_DIR"
    cp -r "$DOCKER_CONFIG_DIR" "$BACKUP_DIR"
    echo -e "${BLUE}Конфигурация сохранена в $BACKUP_DIR${NC}"
    
    read -p "Нажмите любую клавишу для возврата в меню..." -n1 -s
    clear
}# Функция для установки через Docker
install_docker_node() {
    log_message "${GREEN}Начинаем установку ноды Pipe Network Testnet через Docker...${NC}"
    
    # Проверяем установлен ли Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker не установлен. Устанавливаем Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi

    # Создаем директорию для конфигурации
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # Запрашиваем информацию у пользователя
    echo -e "${BLUE}Теперь создадим конфигурационный файл с вашей информацией${NC}"
    echo
    read -p "Введите ваше имя POP: " pop_name
    read -p "Введите ваш город и страну (например, Москва, Россия): " pop_location
    read -p "Введите ваш пригласительный код из письма: " invite_code
    read -p "Введите имя вашей ноды: " node_name
    read -p "Введите ваше полное имя: " full_name
    read -p "Введите ваш адрес электронной почты: " email
    read -p "Введите ваш веб-сайт (или нажмите Enter для пропуска): " website
    read -p "Введите ваше имя пользователя Discord (или нажмите Enter для пропуска): " discord
    read -p "Введите ваш ник Telegram (или нажмите Enter для пропуска): " telegram
    read -p "Введите ваш публичный ключ Solana (адрес кошелька): " solana_pubkey
    
    # Запрашиваем параметры кэширования
    echo -e "${BLUE}Сколько памяти вы хотите выделить для кэша? (в МБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: 4096 для серверов с 8ГБ+ ОЗУ, 2048 для меньших серверов${NC}"
    read -p "Введите размер памяти (по умолчанию: 4096): " memory_cache_size
    memory_cache_size=${memory_cache_size:-4096}
    
    echo -e "${BLUE}Сколько дискового пространства вы хотите выделить для кэша? (в ГБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: минимум 100ГБ${NC}"
    read -p "Введите размер дискового кэша в ГБ (по умолчанию: 100): " disk_cache_size
    disk_cache_size=${disk_cache_size:-100}
    
    # Создаем конфигурационный файл
    echo -e "${GREEN}Создаем конфигурационный файл...${NC}"
    cat > "$DOCKER_CONFIG_DIR/config.json" << EOL
{
  "pop_name": "$pop_name",
  "pop_location": "$pop_location",
  "invite_code": "$invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": 40
  },
  "cache_config": {
    "memory_cache_size_mb": $memory_cache_size,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $disk_cache_size,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$node_name",
    "name": "$full_name",
    "email": "$email",
    "website": "$website",
    "discord": "$discord",
    "telegram": "$telegram",
    "solana_pubkey": "$solana_pubkey"
  }
}
EOL

    # Создаем Docker volume для данных кэша
    echo -e "${GREEN}Создаем Docker volume для данных...${NC}"
    docker volume create "$DOCKER_VOLUME_NAME"
    
    # Останавливаем существующий контейнер, если такой есть
    if docker ps -a | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${YELLOW}Останавливаем существующий контейнер...${NC}"
        docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
        docker rm "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # Открываем порты в фаерволе
    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}Открываем порты в фаерволе...${NC}"
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    
    # Запускаем контейнер Docker
    echo -e "${GREEN}Запускаем контейнер Docker с нодой Pipe Network...${NC}"
    docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        --restart always \
        -p 80:80 \
        -p 443:443 \
        -v "$DOCKER_CONFIG_DIR/config.json:/opt/popcache/config.json" \
        -v "$DOCKER_VOLUME_NAME:/opt/popcache/cache" \
        -e POP_CONFIG_PATH=/opt/popcache/config.json \
        --pull always \
        ubuntu:24.04 /bin/bash -c \
        "apt-get update && \
         apt-get install -y curl wget tar && \
         mkdir -p /opt/popcache/logs && \
         cd /opt/popcache && \
         wget https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz && \
         tar -xzf pop-v0.3.0-linux-*.tar.gz && \
         chmod 755 /opt/popcache/pop && \
         /opt/popcache/pop"
    
    # Проверяем, запустился ли контейнер успешно
    sleep 5
    if docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${GREEN}Контейнер успешно запущен!${NC}"
        echo -e "${BLUE}Проверьте работу ноды:${NC}"
        echo -e "${YELLOW}Состояние: http://$(hostname -I | awk '{print $1}')/state${NC}"
        echo -e "${YELLOW}Проверка здоровья: http://$(hostname -I | awk '{print $1}')/health${NC}"
        echo -e "${GREEN}Нода Pipe Network Testnet успешно установлена через Docker!${NC}"
    else
        echo -e "${RED}Возникла проблема при запуске контейнера Docker.${NC}"
        echo -e "${YELLOW}Проверьте логи контейнера: docker logs $DOCKER_CONTAINER_NAME${NC}"
    fi
    
    # Создаем резервную копию конфигурации
    mkdir -p "$BACKUP_DIR"
    cp -r "$DOCKER_CONFIG_DIR" "$BACKUP_DIR"
    echo -e "${BLUE}Конфигурация сохранена в $BACKUP_DIR${NC}"
    
    read -p "Нажмите любую клавишу для возврата в меню..." -n1 -s
    clear
}# Функция для установки через Docker
install_docker_node() {
    log_message "${GREEN}Начинаем установку ноды Pipe Network Testnet через Docker...${NC}"
    
    # Проверяем установлен ли Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker не установлен. Устанавливаем Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi

    # Создаем директорию для конфигурации
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # Запрашиваем информацию у пользователя
    echo -e "${BLUE}Теперь создадим конфигурационный файл с вашей информацией${NC}"
    echo
    read -p "Введите ваше имя POP: " pop_name
    read -p "Введите ваш город и страну (например, Москва, Россия): " pop_location
    read -p "Введите ваш пригласительный код из письма: " invite_code
    read -p "Введите имя вашей ноды: " node_name
    read -p "Введите ваше полное имя: " full_name
    read -p "Введите ваш адрес электронной почты: " email
    read -p "Введите ваш веб-сайт (или нажмите Enter для пропуска): " website
    read -p "Введите ваше имя пользователя Discord (или нажмите Enter для пропуска): " discord
    read -p "Введите ваш ник Telegram (или нажмите Enter для пропуска): " telegram
    read -p "Введите ваш публичный ключ Solana (адрес кошелька): " solana_pubkey
    
    # Запрашиваем параметры кэширования
    echo -e "${BLUE}Сколько памяти вы хотите выделить для кэша? (в МБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: 4096 для серверов с 8ГБ+ ОЗУ, 2048 для меньших серверов${NC}"
    read -p "Введите размер памяти (по умолчанию: 4096): " memory_cache_size
    memory_cache_size=${memory_cache_size:-4096}
    
    echo -e "${BLUE}Сколько дискового пространства вы хотите выделить для кэша? (в ГБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: минимум 100ГБ${NC}"
    read -p "Введите размер дискового кэша в ГБ (по умолчанию: 100): " disk_cache_size
    disk_cache_size=${disk_cache_size:-100}
    
    # Создаем конфигурационный файл
    echo -e "${GREEN}Создаем конфигурационный файл...${NC}"
    cat > "$DOCKER_CONFIG_DIR/config.json" << EOL
{
  "pop_name": "$pop_name",
  "pop_location": "$pop_location",
  "invite_code": "$invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": 40
  },
  "cache_config": {
    "memory_cache_size_mb": $memory_cache_size,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $disk_cache_size,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$node_name",
    "name": "$full_name",
    "email": "$email",
    "website": "$website",
    "discord": "$discord",
    "telegram": "$telegram",
    "solana_pubkey": "$solana_pubkey"
  }
}
EOL

    # Создаем Docker volume для данных кэша
    echo -e "${GREEN}Создаем Docker volume для данных...${NC}"
    docker volume create "$DOCKER_VOLUME_NAME"
    
    # Останавливаем существующий контейнер, если такой есть
    if docker ps -a | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${YELLOW}Останавливаем существующий контейнер...${NC}"
        docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
        docker rm "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # Открываем порты в фаерволе
    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}Открываем порты в фаерволе...${NC}"
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    
    # Запускаем контейнер Docker
    echo -e "${GREEN}Запускаем контейнер Docker с нодой Pipe Network...${NC}"
    docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        --restart always \
        -p 80:80 \
        -p 443:443 \
        -v "$DOCKER_CONFIG_DIR/config.json:/opt/popcache/config.json" \
        -v "$DOCKER_VOLUME_NAME:/opt/popcache/cache" \
        -e POP_CONFIG_PATH=/opt/popcache/config.json \
        --pull always \
        ubuntu:24.04 /bin/bash -c \
        "apt-get update && \
         apt-get install -y curl wget tar && \
         mkdir -p /opt/popcache/logs && \
         cd /opt/popcache && \
         wget https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz && \
         tar -xzf pop-v0.3.0-linux-*.tar.gz && \
         chmod 755 /opt/popcache/pop && \
         /opt/popcache/pop"
    
    # Проверяем, запустился ли контейнер успешно
    sleep 5
    if docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${GREEN}Контейнер успешно запущен!${NC}"
        echo -e "${BLUE}Проверьте работу ноды:${NC}"
        echo -e "${YELLOW}Состояние: http://$(hostname -I | awk '{print $1}')/state${NC}"
        echo -e "${YELLOW}Проверка здоровья: http://$(hostname -I | awk '{print $1}')/health${NC}"
        echo -e "${GREEN}Нода Pipe Network Testnet успешно установлена через Docker!${NC}"
    else
        echo -e "${RED}Возникла проблема при запуске контейнера Docker.${NC}"
        echo -e "${YELLOW}Проверьте логи контейнера: docker logs $DOCKER_CONTAINER_NAME${NC}"
    fi
    
    # Создаем резервную копию конфигурации
    mkdir -p "$BACKUP_DIR"
    cp -r "$DOCKER_CONFIG_DIR" "$BACKUP_DIR"
    echo -e "${BLUE}Конфигурация сохранена в $BACKUP_DIR${NC}"
    
    read -p "Нажмите любую клавишу для возврата в меню..." -n1 -s
    clear
}# Функция для установки через Docker
install_docker_node() {
    log_message "${GREEN}Начинаем установку ноды Pipe Network Testnet через Docker...${NC}"
    
    # Проверяем установлен ли Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker не установлен. Устанавливаем Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi

    # Создаем директорию для конфигурации
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # Запрашиваем информацию у пользователя
    echo -e "${BLUE}Теперь создадим конфигурационный файл с вашей информацией${NC}"
    echo
    read -p "Введите ваше имя POP: " pop_name
    read -p "Введите ваш город и страну (например, Москва, Россия): " pop_location
    read -p "Введите ваш пригласительный код из письма: " invite_code
    read -p "Введите имя вашей ноды: " node_name
    read -p "Введите ваше полное имя: " full_name
    read -p "Введите ваш адрес электронной почты: " email
    read -p "Введите ваш веб-сайт (или нажмите Enter для пропуска): " website
    read -p "Введите ваше имя пользователя Discord (или нажмите Enter для пропуска): " discord
    read -p "Введите ваш ник Telegram (или нажмите Enter для пропуска): " telegram
    read -p "Введите ваш публичный ключ Solana (адрес кошелька): " solana_pubkey
    
    # Запрашиваем параметры кэширования
    echo -e "${BLUE}Сколько памяти вы хотите выделить для кэша? (в МБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: 4096 для серверов с 8ГБ+ ОЗУ, 2048 для меньших серверов${NC}"
    read -p "Введите размер памяти (по умолчанию: 4096): " memory_cache_size
    memory_cache_size=${memory_cache_size:-4096}
    
    echo -e "${BLUE}Сколько дискового пространства вы хотите выделить для кэша? (в ГБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: минимум 100ГБ${NC}"
    read -p "Введите размер дискового кэша в ГБ (по умолчанию: 100): " disk_cache_size
    disk_cache_size=${disk_cache_size:-100}
    
    # Создаем конфигурационный файл
    echo -e "${GREEN}Создаем конфигурационный файл...${NC}"
    cat > "$DOCKER_CONFIG_DIR/config.json" << EOL
{
  "pop_name": "$pop_name",
  "pop_location": "$pop_location",
  "invite_code": "$invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": 40
  },
  "cache_config": {
    "memory_cache_size_mb": $memory_cache_size,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $disk_cache_size,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$node_name",
    "name": "$full_name",
    "email": "$email",
    "website": "$website",
    "discord": "$discord",
    "telegram": "$telegram",
    "solana_pubkey": "$solana_pubkey"
  }
}
EOL

    # Создаем Docker volume для данных кэша
    echo -e "${GREEN}Создаем Docker volume для данных...${NC}"
    docker volume create "$DOCKER_VOLUME_NAME"
    
    # Останавливаем существующий контейнер, если такой есть
    if docker ps -a | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${YELLOW}Останавливаем существующий контейнер...${NC}"
        docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
        docker rm "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # Открываем порты в фаерволе
    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}Открываем порты в фаерволе...${NC}"
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    
    # Запускаем контейнер Docker
    echo -e "${GREEN}Запускаем контейнер Docker с нодой Pipe Network...${NC}"
    docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        --restart always \
        -p 80:80 \
        -p 443:443 \
        -v "$DOCKER_CONFIG_DIR/config.json:/opt/popcache/config.json" \
        -v "$DOCKER_VOLUME_NAME:/opt/popcache/cache" \
        -e POP_CONFIG_PATH=/opt/popcache/config.json \
        --pull always \
        ubuntu:24.04 /bin/bash -c \
        "apt-get update && \
         apt-get install -y curl wget tar && \
         mkdir -p /opt/popcache/logs && \
         cd /opt/popcache && \
         wget https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz && \
         tar -xzf pop-v0.3.0-linux-*.tar.gz && \
         chmod 755 /opt/popcache/pop && \
         /opt/popcache/pop"
    
    # Проверяем, запустился ли контейнер успешно
    sleep 5
    if docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${GREEN}Контейнер успешно запущен!${NC}"
        echo -e "${BLUE}Проверьте работу ноды:${NC}"
        echo -e "${YELLOW}Состояние: http://$(hostname -I | awk '{print $1}')/state${NC}"
        echo -e "${YELLOW}Проверка здоровья: http://$(hostname -I | awk '{print $1}')/health${NC}"
        echo -e "${GREEN}Нода Pipe Network Testnet успешно установлена через Docker!${NC}"
    else
        echo -e "${RED}Возникла проблема при запуске контейнера Docker.${NC}"
        echo -e "${YELLOW}Проверьте логи контейнера: docker logs $DOCKER_CONTAINER_NAME${NC}"
    fi
    
    # Создаем резервную копию конфигурации
    mkdir -p "$BACKUP_DIR"
    cp -r "$DOCKER_CONFIG_DIR" "$BACKUP_DIR"
    echo -e "${BLUE}Конфигурация сохранена в $BACKUP_DIR${NC}"
    
    read -p "Нажмите любую клавишу для возврата в меню..." -n1 -s
    clear
}# Функция для установки через Docker
install_docker_node() {
    log_message "${GREEN}Начинаем установку ноды Pipe Network Testnet через Docker...${NC}"
    
    # Проверяем установлен ли Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker не установлен. Устанавливаем Docker...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi

    # Создаем директорию для конфигурации
    mkdir -p "$DOCKER_CONFIG_DIR"
    
    # Запрашиваем информацию у пользователя
    echo -e "${BLUE}Теперь создадим конфигурационный файл с вашей информацией${NC}"
    echo
    read -p "Введите ваше имя POP: " pop_name
    read -p "Введите ваш город и страну (например, Москва, Россия): " pop_location
    read -p "Введите ваш пригласительный код из письма: " invite_code
    read -p "Введите имя вашей ноды: " node_name
    read -p "Введите ваше полное имя: " full_name
    read -p "Введите ваш адрес электронной почты: " email
    read -p "Введите ваш веб-сайт (или нажмите Enter для пропуска): " website
    read -p "Введите ваше имя пользователя Discord (или нажмите Enter для пропуска): " discord
    read -p "Введите ваш ник Telegram (или нажмите Enter для пропуска): " telegram
    read -p "Введите ваш публичный ключ Solana (адрес кошелька): " solana_pubkey
    
    # Запрашиваем параметры кэширования
    echo -e "${BLUE}Сколько памяти вы хотите выделить для кэша? (в МБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: 4096 для серверов с 8ГБ+ ОЗУ, 2048 для меньших серверов${NC}"
    read -p "Введите размер памяти (по умолчанию: 4096): " memory_cache_size
    memory_cache_size=${memory_cache_size:-4096}
    
    echo -e "${BLUE}Сколько дискового пространства вы хотите выделить для кэша? (в ГБ)${NC}"
    echo -e "${YELLOW}Рекомендуется: минимум 100ГБ${NC}"
    read -p "Введите размер дискового кэша в ГБ (по умолчанию: 100): " disk_cache_size
    disk_cache_size=${disk_cache_size:-100}
    
    # Создаем конфигурационный файл
    echo -e "${GREEN}Создаем конфигурационный файл...${NC}"
    cat > "$DOCKER_CONFIG_DIR/config.json" << EOL
{
  "pop_name": "$pop_name",
  "pop_location": "$pop_location",
  "invite_code": "$invite_code",
  "server": {
    "host": "0.0.0.0",
    "port": 443,
    "http_port": 80,
    "workers": 40
  },
  "cache_config": {
    "memory_cache_size_mb": $memory_cache_size,
    "disk_cache_path": "./cache",
    "disk_cache_size_gb": $disk_cache_size,
    "default_ttl_seconds": 86400,
    "respect_origin_headers": true,
    "max_cacheable_size_mb": 1024
  },
  "api_endpoints": {
    "base_url": "https://dataplane.pipenetwork.com"
  },
  "identity_config": {
    "node_name": "$node_name",
    "name": "$full_name",
    "email": "$email",
    "website": "$website",
    "discord": "$discord",
    "telegram": "$telegram",
    "solana_pubkey": "$solana_pubkey"
  }
}
EOL

    # Создаем Docker volume для данных кэша
    echo -e "${GREEN}Создаем Docker volume для данных...${NC}"
    docker volume create "$DOCKER_VOLUME_NAME"
    
    # Останавливаем существующий контейнер, если такой есть
    if docker ps -a | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${YELLOW}Останавливаем существующий контейнер...${NC}"
        docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
        docker rm "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    # Открываем порты в фаерволе
    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}Открываем порты в фаерволе...${NC}"
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    
    # Запускаем контейнер Docker
    echo -e "${GREEN}Запускаем контейнер Docker с нодой Pipe Network...${NC}"
    docker run -d \
        --name "$DOCKER_CONTAINER_NAME" \
        --restart always \
        -p 80:80 \
        -p 443:443 \
        -v "$DOCKER_CONFIG_DIR/config.json:/opt/popcache/config.json" \
        -v "$DOCKER_VOLUME_NAME:/opt/popcache/cache" \
        -e POP_CONFIG_PATH=/opt/popcache/config.json \
        --pull always \
        ubuntu:24.04 /bin/bash -c \
        "apt-get update && \
         apt-get install -y curl wget tar && \
         mkdir -p /opt/popcache/logs && \
         cd /opt/popcache && \
         wget https://download.pipe.network/static/pop-v0.3.0-linux-x64.tar.gz && \
         tar -xzf pop-v0.3.0-linux-*.tar.gz && \
         chmod 755 /opt/popcache/pop && \
         /opt/popcache/pop"
    
    # Проверяем, запустился ли контейнер успешно
    sleep 5
    if docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${GREEN}Контейнер успешно запущен!${NC}"
        echo -e "${BLUE}Проверьте работу ноды:${NC}"
        echo -e "${YELLOW}Состояние: http://$(hostname -I | awk '{print $1}')/state${NC}"
        echo -e "${YELLOW}Проверка здоровья: http://$(hostname -I | awk '{print $1}')/health${NC}"
        echo -e "${GREEN}Нода Pipe Network Testnet успешно установлена через Docker!${NC}"
    else
        echo -e "${RED}Возникла проблема при запуске контейнера Docker.${NC}"
        echo -e "${YELLOW}Проверьте логи контейнера: docker logs $DOCKER_CONTAINER_NAME${NC}"
    fi
    
    # Создаем резервную копию конфигурации
    mkdir -p "$BACKUP_DIR"
    cp -r "$DOCKER_CONFIG_DIR" "$BACKUP_DIR"
    echo -e "${BLUE}Конфигурация сохранена в $BACKUP_DIR${NC}"
    
    read -p "Нажмите любую клавишу для возврата в меню..." -n1 -s
    clear
}# В функцию monitor_node, после существующего кода
    # Проверка Docker-контейнера
    if command -v docker &> /dev/null && docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        echo -e "${BLUE}Docker-контейнер с нодой Pipe Network обнаружен${NC}"
        echo "1. Проверить статус контейнера"
        echo "2. Показать логи контейнера"
        echo "3. Перезапустить контейнер"
        echo "4. Проверить порты 80 и 443"
        echo "5. Проверить состояние ноды в контейнере"
        echo "6. Назад"
        read -p "Выберите опцию: " docker_choice
        
        case $docker_choice in
            1)
                echo -e "${YELLOW}Статус Docker-контейнера:${NC}"
                docker ps -a | grep "$DOCKER_CONTAINER_NAME"
                ;;
            2)
                echo -e "${YELLOW}Последние логи Docker-контейнера:${NC}"
                docker logs --tail 50 "$DOCKER_CONTAINER_NAME"
                ;;
            3)
                echo -e "${YELLOW}Перезапускаем Docker-контейнер...${NC}"
                docker restart "$DOCKER_CONTAINER_NAME"
                echo -e "${GREEN}Контейнер перезапущен.${NC}"
                ;;
            4)
                echo -e "${YELLOW}Проверка портов 80 и 443:${NC}"
                echo "Порт 80:"
                ss -tulpn | grep ":80\s"
                echo "Порт 443:"
                ss -tulpn | grep ":443\s"
                ;;
            5)
                server_ip=$(hostname -I | awk '{print $1}')
                echo -e "${YELLOW}Проверка состояния ноды:${NC}"
                echo -e "${BLUE}Проверяем: http://$server_ip/state${NC}"
                curl -s "http://$server_ip/state" | jq .
                echo -e "${BLUE}Проверка здоровья: http://$server_ip/health${NC}"
                curl -s "http://$server_ip/health"
                echo
                ;;
            6)
                return
                ;;
            *)
                echo -e "${RED}Неверный выбор${NC}"
                ;;
        esac
    fi