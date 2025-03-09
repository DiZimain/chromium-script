#!/bin/bash

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

# Запрос использования прокси
read -p "Использовать прокси? (y/n): " use_proxy
if [[ "$use_proxy" != "y" && "$use_proxy" != "n" ]]; then
    echo "Ошибка: введите 'y' (да) или 'n' (нет)."
    exit 1
fi

# Базовый порт для веб-интерфейса
base_port=3100  # Изменён с 3000 на 3100, чтобы избежать конфликтов

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
    container_name="chromium$i"
    port=$((base_port + i - 1))
    
    # Формируем команду
    cmd="docker run -d --name $container_name -p $port:3000 linuxserver/chromium"
    
    # Добавляем прокси, если они есть
    if [ "$use_proxy" == "y" ] && [ $((i-1)) -lt ${#proxies[@]} ]; then
        proxy=${proxies[$((i-1))]}
        IFS=':' read -r ip port login pass <<< "$proxy"
        cmd="docker run -d --name $container_name -p $port:3000 -e HTTP_PROXY=\"http://$login:$pass@$ip:$port\" -e HTTPS_PROXY=\"http://$login:$pass@$ip:$port\" linuxserver/chromium"
    fi
    
    # Выполняем команду
    echo "Запускаем $container_name на порту $port..."
    eval "$cmd"
done

# Вывод результатов
echo "Контейнеры запущены. Подключитесь через браузер:"
for ((i=1; i<=num_profiles; i++)); do
    port=$((base_port + i - 1))
    echo "Профиль $i: http://<IP_сервера>:$port"
done
echo "Узнайте IP сервера командой: curl ifconfig.me"
echo "Для доступа используйте SSH-туннель, если сервер не публичный: ssh -L <порт>:localhost:<порт> root@<IP_сервера>"
