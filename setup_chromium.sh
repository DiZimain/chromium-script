#!/bin/bash

# ██████╗ ██╗███████╗██╗███╗   ███╗ █████╗ ██╗███╗   ██╗
# ██╔══██╗██║╚══███╔╝██║████╗ ████║██╔══██╗██║████╗  ██║
# ██║  ██║██║  ███╔╝ ██║██╔████╔██║███████║██║██╔██╗ ██║
# ██║  ██║██║ ███╔╝  ██║██║╚██╔╝██║██╔══██║██║██║╚██╗██║
# ██████╔╝██║███████╗██║██║ ╚═╝ ██║██║  ██║██║██║ ╚████║
# ╚═════╝ ╚═╝╚══════╝╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝
#
# Chromium Containers Manager
# Версия: 1.1
# Описание: Скрипт для управления контейнерами Chromium с поддержкой прокси

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка наличия Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker не установлен. Устанавливаем...${NC}"
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
        echo -e "${GREEN}Docker установлен. Пожалуйста, перезапустите сессию для применения изменений.${NC}"
        exit 1
    else
        echo -e "${GREEN}Docker уже установлен.${NC}"
    fi
}

# Функция для проверки, существует ли контейнер с указанным именем
container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^$1$"
}

# Функция для проверки, запущен ли контейнер с указанным именем
container_running() {
    docker ps --format '{{.Names}}' | grep -q "^$1$"
}

# Функция для создания контейнера с Chromium
create_chromium_container() {
    local container_name=$1
    local port=$2
    local proxy=$3
    
    # Проверяем, существует ли уже контейнер с таким именем
    if container_exists "$container_name"; then
        echo -e "${YELLOW}Контейнер $container_name уже существует.${NC}"
        
        # Если контейнер не запущен, запускаем его
        if ! container_running "$container_name"; then
            echo -e "${BLUE}Запускаем существующий контейнер $container_name...${NC}"
            docker start "$container_name"
            echo -e "${GREEN}Контейнер $container_name запущен на порту $port.${NC}"
        else
            echo -e "${GREEN}Контейнер $container_name уже запущен.${NC}"
        fi
        return
    fi
    
    # Базовая команда для создания контейнера
    local cmd="docker run -d --name $container_name -p $port:3000"
    
    # Добавляем переменные окружения для прокси, если они указаны
    if [ -n "$proxy" ]; then
        # Разбиваем строку прокси на компоненты
        IFS=':' read -r proxy_ip proxy_port proxy_login proxy_pass <<< "$proxy"
        
        if [ -n "$proxy_ip" ] && [ -n "$proxy_port" ]; then
            # Формируем прокси URL
            if [ -n "$proxy_login" ] && [ -n "$proxy_pass" ]; then
                proxy_url="http://$proxy_login:$proxy_pass@$proxy_ip:$proxy_port"
            else
                proxy_url="http://$proxy_ip:$proxy_port"
            fi
            
            # Добавляем переменные окружения для прокси
            cmd+=" -e HTTP_PROXY=\"$proxy_url\" -e HTTPS_PROXY=\"$proxy_url\" -e NO_PROXY=\"localhost,127.0.0.1\""
        fi
    fi
    
    # Добавляем имя образа
    cmd+=" linuxserver/chromium"
    
    # Запускаем контейнер
    echo -e "${BLUE}Создаем и запускаем контейнер $container_name...${NC}"
    eval $cmd
    echo -e "${GREEN}Контейнер $container_name создан и запущен на порту $port.${NC}"
    
    # Даем контейнеру время на инициализацию
    sleep 2
    
    # Выводим информацию о доступе
    echo -e "${GREEN}Доступ к Chromium в контейнере $container_name:${NC}"
    echo -e "URL: http://localhost:$port или http://$(curl -s ifconfig.me):$port"
    echo -e "Логин по умолчанию: abc"
    echo -e "Пароль по умолчанию: abc"
}

# Функция для остановки и удаления контейнера
remove_chromium_container() {
    local container_name=$1
    
    if container_exists "$container_name"; then
        echo -e "${BLUE}Останавливаем и удаляем контейнер $container_name...${NC}"
        docker stop "$container_name" >/dev/null 2>&1
        docker rm "$container_name" >/dev/null 2>&1
        echo -e "${GREEN}Контейнер $container_name удален.${NC}"
    else
        echo -e "${YELLOW}Контейнер $container_name не существует.${NC}"
    fi
}

# Функция для отображения списка контейнеров
list_chromium_containers() {
    echo -e "${BLUE}Список контейнеров Chromium:${NC}"
    docker ps -a --filter "ancestor=linuxserver/chromium" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Функция для отображения справки
show_help() {
    echo "Использование: $0 [опции]"
    echo ""
    echo "Опции:"
    echo "  create <имя> <порт> [прокси]      Создать новый контейнер с Chromium"
    echo "                                    Формат прокси: ip:port:login:pass"
    echo "  remove <имя>                      Удалить контейнер"
    echo "  list                              Показать список всех контейнеров Chromium"
    echo "  help                              Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 create chromium1 3001                      # Создать контейнер без прокси"
    echo "  $0 create chromium2 3002 192.168.1.1:8080     # Создать с прокси без аутентификации"
    echo "  $0 create chromium3 3003 192.168.1.1:8080:user:pass  # Создать с прокси и аутентификацией"
    echo "  $0 remove chromium1                           # Удалить контейнер"
    echo "  $0 list                                       # Показать список контейнеров"
}

# Интерактивное меню
show_interactive_menu() {
    clear
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}        DIZIMAIN CHROMIUM MANAGER        ${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    echo -e "1) ${GREEN}Создать контейнер${NC}"
    echo -e "2) ${RED}Удалить контейнер${NC}"
    echo -e "3) ${BLUE}Показать список контейнеров${NC}"
    echo -e "4) ${YELLOW}Выход${NC}"
    echo ""
    echo -n "Выберите опцию (1-4): "
    read choice

    case $choice in
        1)
            echo -n "Введите имя контейнера (например, chromium1): "
            read container_name
            echo -n "Введите порт (например, 3001): "
            read port
            echo -n "Использовать прокси? (y/n): "
            read use_proxy
            
            if [[ "$use_proxy" == "y" || "$use_proxy" == "Y" ]]; then
                echo -n "Введите прокси в формате ip:port:login:pass: "
                read proxy
                create_chromium_container "$container_name" "$port" "$proxy"
            else
                create_chromium_container "$container_name" "$port"
            fi
            ;;
        2)
            echo -n "Введите имя контейнера для удаления: "
            read container_name
            remove_chromium_container "$container_name"
            ;;
        3)
            list_chromium_containers
            ;;
        4)
            echo -e "${GREEN}До свидания!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор!${NC}"
            ;;
    esac
    
    echo ""
    echo -n "Нажмите Enter для возврата в меню..."
    read
    show_interactive_menu
}

# Главная функция
main() {
    # Проверяем наличие Docker
    check_docker
    
    # Если аргументы не переданы, показываем интерактивное меню
    if [ $# -eq 0 ]; then
        show_interactive_menu
        exit 0
    fi
    
    # Обрабатываем аргументы командной строки
    local action=$1
    
    case $action in
        create)
            # Проверяем наличие необходимых аргументов
            if [ -z "$2" ] || [ -z "$3" ]; then
                echo -e "${RED}Ошибка: Необходимо указать имя контейнера и порт.${NC}"
                show_help
                exit 1
            fi
            
            create_chromium_container "$2" "$3" "$4"
            ;;
        remove)
            # Проверяем наличие необходимых аргументов
            if [ -z "$2" ]; then
                echo -e "${RED}Ошибка: Необходимо указать имя контейнера.${NC}"
                show_help
                exit 1
            fi
            
            remove_chromium_container "$2"
            ;;
        list)
            list_chromium_containers
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Неизвестное действие: $action${NC}"
            show_help
            exit 1
            ;;
    esac
}

# Запускаем главную функцию с переданными аргументами
main "$@"