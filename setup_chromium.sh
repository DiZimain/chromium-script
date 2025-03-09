#!/bin/bash
set -e

echo "======================================================"
echo "    Скрипт для создания контейнеров с Chromium"
echo "======================================================"

# Проверка наличия Docker
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

# Запрос количества профилей
read -p "Сколько профилей Chromium создать? (введите число): " num_profiles
if ! [[ "$num_profiles" =~ ^[0-9]+$ ]] || [ "$num_profiles" -lt 1 ]; then
    echo "Ошибка: введите положительное число."
    exit 1
fi

# Запрос префикса имени
read -p "Введите префикс имени для контейнеров (например, chrome): " name_prefix
if [ -z "$name_prefix" ]; then
    name_prefix="chrome-$(date +%Y%m%d)"
fi
name_prefix=$(echo "$name_prefix" | tr -dc 'a-zA-Z0-9-')

# Запрос использования прокси
read -p "Использовать прокси? (y/n): " use_proxy
if [[ "$use_proxy" != "y" && "$use_proxy" != "n" ]]; then
    echo "Ошибка: введите 'y' (да) или 'n' (нет)."
    exit 1
fi

# Базовый порт
base_port=9000

# Массив для прокси
declare -a proxies

# Запрос прокси, если нужно
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
        echo "Предупреждение: указано меньше прокси (${#proxies[@]}) чем профилей ($num_profiles)."
        echo "Оставшиеся профили будут без прокси."
    fi
fi

# Очистка существующих контейнеров с таким же префиксом
echo "Проверяем наличие существующих контейнеров..."
existing_containers=$(docker ps -a --format "{{.Names}}" | grep "^$name_prefix-" 2>/dev/null || true)
if [ -n "$existing_containers" ]; then
    echo "Найдены существующие контейнеры. Удаляем:"
    for container in $existing_containers; do
        echo "  - Останавливаем и удаляем $container"
        docker stop $container >/dev/null 2>&1 || true
        docker rm $container >/dev/null 2>&1 || true
    done
    echo "Существующие контейнеры удалены."
fi

# Запускаем новые контейнеры
echo "======================================================"
echo "Запускаем контейнеры с Chromium..."
echo "======================================================"

for ((i=1; i<=num_profiles; i++)); do
    container_name="${name_prefix}-${i}"
    port=$((base_port + i))
    
    echo "Создаю контейнер $container_name (порт $port)..."
    
    # Базовые опции для запуска контейнера
    docker_cmd="docker run -d \
        --name $container_name \
        -p $port:3000 \
        -e TZ=Europe/Moscow \
        -e PUID=1000 \
        -e PGID=1000"
    
    # Добавляем прокси если нужно
    if [ "$use_proxy" == "y" ] && [ $((i-1)) -lt ${#proxies[@]} ]; then
        proxy="${proxies[$((i-1))]}"
        IFS=':' read -r proxy_ip proxy_port proxy_login proxy_pass <<< "$proxy"
        
        # Экранируем специальные символы в логине и пароле прокси
        proxy_login_esc=$(printf '%s' "$proxy_login" | sed 's/[&/\]/\\&/g')
        proxy_pass_esc=$(printf '%s' "$proxy_pass" | sed 's/[&/\]/\\&/g')
        
        docker_cmd="$docker_cmd \
            -e HTTP_PROXY=http://${proxy_login_esc}:${proxy_pass_esc}@${proxy_ip}:${proxy_port} \
            -e HTTPS_PROXY=http://${proxy_login_esc}:${proxy_pass_esc}@${proxy_ip}:${proxy_port}"
    fi
    
    # Добавляем имя образа и запускаем
    docker_cmd="$docker_cmd dorowu/ubuntu-desktop-lxde-vnc:focal"
    
    # Запуск контейнера
    container_id=$(eval "$docker_cmd" 2>/dev/null || echo "ERROR")
    if [ "$container_id" == "ERROR" ]; then
        echo "❌ Ошибка при запуске контейнера $container_name!"
        echo "Попробуйте запустить контейнер вручную для просмотра подробной ошибки:"
        echo "$docker_cmd"
    else
        echo "✅ Контейнер $container_name успешно запущен (ID: ${container_id:0:12})"
    fi
done

# Вывод результатов
echo "======================================================"
echo "🎉 ГОТОВО! Контейнеры запущены."
echo "======================================================"
echo "Ваш IP-адрес: $(curl -s ifconfig.me || echo "<не удалось определить>")"
echo ""
echo "Доступные профили:"
for ((i=1; i<=num_profiles; i++)); do
    port=$((base_port + i))
    echo "Профиль $i: http://<IP_сервера>:$port"
done
echo ""
echo "⚠️ Для доступа подключитесь через браузер по адресу http://<IP>:<порт>"
echo "📝 Логин и пароль по умолчанию: admin/admin"
echo ""
echo "🔄 Чтобы перезапустить все контейнеры, выполните:"
echo "bash $0"
echo ""
echo "❌ Чтобы удалить все контейнеры, выполните:"
echo "docker stop \$(docker ps -a --format '{{.Names}}' | grep '^$name_prefix-') 2>/dev/null || true"
echo "docker rm \$(docker ps -a --format '{{.Names}}' | grep '^$name_prefix-') 2>/dev/null || true"