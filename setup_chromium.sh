#!/bin/bash
set -e

# Проверка, установлен ли Docker
if ! command -v docker &> /dev/null; then
    echo "Docker не установлен. Устанавливаем..."
    sudo apt update
    sudo apt install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER
    echo "Docker установлен. Пожалуйста, перелогиньтесь и запустите скрипт снова."
    exit 1
fi

# Запрос количества Chromium-профилей
read -p "Сколько профилей Chromium создать? (введите число): " num_profiles
if ! [[ "$num_profiles" =~ ^[0-9]+$ ]] || [ "$num_profiles" -lt 1 ]; then
    echo "Ошибка: введите положительное число."
    exit 1
fi

# Запрос префикса имени контейнеров
read -p "Введите префикс имени для контейнеров (например, chrome-2025-03-10) или оставьте пустым для автоматического имени: " name_prefix
if [ -z "$name_prefix" ]; then
    # Если пользователь не ввёл префикс, генерируем его с временной меткой
    name_prefix="chrome-$(date +%Y%m%d-%H%M%S)"
fi
# Убедимся, что префикс не содержит недопустимых символов
name_prefix=$(echo "$name_prefix" | tr -dc 'a-zA-Z0-9-')

# Запрос использования прокси
read -p "Использовать прокси? (y/n): " use_proxy
if [[ "$use_proxy" != "y" && "$use_proxy" != "n" ]]; then
    echo "Ошибка: введите 'y' (да) или 'n' (нет)."
    exit 1
fi

# Базовый порт для веб-интерфейса
base_port=3100

# Массив для хранения данных прокси
declare -a proxies

# Если выбраны прокси, запрашиваем данные
if [ "$use_proxy" == "y" ]; then
    echo "Введите данные прокси в формате ip:port:login:pass (по одному на строку)."
    echo "Для завершения ввода оставьте строку пустой и нажмите Enter."
    for ((i=1; i<=num_profiles; i++)); do
        read -p "Прокси для профиля $i: " proxy_input
        if [ -z "$proxy_input" ]; then
            if [ $i -eq 1 ]; then
                echo "Ошибка: введите хотя бы один прокси или выберите 'n' для работы без прокси."
                exit 1
            fi
            break
        fi
        proxies+=("$proxy_input")
    done
    if [ ${#proxies[@]} -lt $num_profiles ]; then
        echo "Предупреждение: указано меньше прокси (${#proxies[@]}) чем профилей ($num_profiles). Оставшиеся профили будут без прокси."
    fi
fi

# Запуск контейнеров
echo "Запускаем контейнеры..."
for ((i=1; i<=num_profiles; i++)); do
    container_name="${name_prefix}-${i}"
    port=$((base_port + i - 1))
    
    # Если контейнер с таким именем существует, останавливаем и удаляем его
    if [ "$(docker ps -a -q -f name="^${container_name}$")" ]; then
        echo "Контейнер $container_name уже существует. Останавливаем и удаляем..."
        docker stop "$container_name" > /dev/null 2>&1 || true
        docker rm "$container_name" > /dev/null 2>&1 || true
    fi
    
    # Формируем команду запуска (проброс порта на 3001)
    cmd="docker run -d --name $container_name -p $port:3001"
    
    # Если используются прокси, добавляем переменные окружения
    if [ "$use_proxy" == "y" ] && [ $((i-1)) -lt ${#proxies[@]} ]; then
        proxy=${proxies[$((i-1))]}
        IFS=':' read -r proxy_ip proxy_port proxy_login proxy_pass <<< "$proxy"
        cmd+=" -e HTTP_PROXY=\"http://$proxy_login:$proxy_pass@$proxy_ip:$proxy_port\" -e HTTPS_PROXY=\"http://$proxy_login:$proxy_pass@$proxy_ip:$proxy_port\""
    fi
    
    # Добавляем образ
    cmd+=" linuxserver/chromium"
    
    echo "Выполняем: $cmd"
    if ! output=$(eval "$cmd" 2>&1); then
        echo "Ошибка при запуске $container_name: $output"
    else
        echo "Контейнер $container_name запущен (ID: $output)"
    fi
done

# Вывод результатов
echo "Контейнеры запущены. Подключитесь через браузер:"
for ((i=1; i<=num_profiles; i++)); do
    port=$((base_port + i - 1))
    echo "Профиль $i: http://<IP_сервера>:$port"
done
echo "Узнайте IP сервера командой: curl ifconfig.me"
echo "Для доступа используйте SSH-туннель, если сервер не публичный: ssh -L <порт>:localhost:<порт> root@<IP_сервера>"
