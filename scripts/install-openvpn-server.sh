#!/bin/bash

# ==============================================================================
# Скрипт автоматической установки OpenVPN Antizapret
# Основан на инструкции: https://github.com/gavitt/openvpn-antizapret/blob/main/README.md
#
# ВАЖНО: Запускайте этот скрипт ИЗ ДИРЕКТОРИИ клонированного репозитория!
# ==============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите скрипт от имени root (sudo)${NC}"
  exit 1
fi

# Определяем директорию, из которой запущен скрипт (директория репозитория)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Проверка наличия server.conf в директории репозитория
if [ ! -f "$SCRIPT_DIR/config/server.conf" ]; then
    echo -e "${RED}Ошибка: Файл server.conf не найден в директории $SCRIPT_DIR${NC}"
    echo -e "${YELLOW}Убедитесь, что вы запустили скрипт из директории клонированного репозитория openvpn-antizapret${NC}"
    exit 1
fi

echo -e "${YELLOW}Внимание: Этот скрипт установит и настроит OpenVPN сервер."
echo -e "Все существующие конфигурации в /etc/openvpn/ будут перезаписаны!${NC}"
read -p "Продолжить? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Отмена."
    exit 0
fi

echo -e "${GREEN}Начало автоматической установки OpenVPN Antizapret...${NC}"
echo -e "${GREEN}Директория репозитория: $SCRIPT_DIR${NC}"

# 1. Установка необходимых пакетов
echo -e "${YELLOW}[1/11] Установка необходимых пакетов...${NC}"
export DEBIAN_FRONTEND=noninteractive
# Предварительная настройка iptables-persistent, чтобы избежать интерактивных prompts
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections

apt update
apt install -y openvpn easy-rsa iptables-persistent debconf-utils

# 2. Настройка Easy-RSA
echo -e "${YELLOW}[2/11] Настройка Easy-RSA...${NC}"
rm -rf /etc/openvpn/easy-rsa
cp -R /usr/share/easy-rsa /etc/openvpn
cd /etc/openvpn/easy-rsa/

# Создание файла vars
cat <<EOF > vars
set_var EASYRSA_KEY_SIZE 2048
set_var EASYRSA_ALGO rsa
set_var EASYRSA_REQ_CN "OpenVPN-CA"
EOF

# 3. Инициализация PKI и создание сертификатов
echo -e "${YELLOW}[3/11] Инициализация PKI и создание CA...${NC}"
ln -s openssl-easyrsa.cnf openssl.cnf
./easyrsa init-pki
EASYRSA_BATCH=1 ./easyrsa build-ca nopass

echo -e "${YELLOW}[4/11] Создание сертификата сервера...${NC}"
EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass

echo -e "${YELLOW}[5/11] Создание сертификата клиента...${NC}"
EASYRSA_BATCH=1 ./easyrsa build-client-full client nopass

echo -e "${YELLOW}[6/11] Генерация параметров Диффи-Хеллмана (может занять несколько минут)...${NC}"
openssl dhparam -out /etc/openvpn/dh.pem 2048

# 4. Копирование сертификатов
echo -e "${YELLOW}[7/11] Копирование сертификатов...${NC}"
cp pki/ca.crt /etc/openvpn/
cp pki/issued/server.crt /etc/openvpn/
cp pki/private/server.key /etc/openvpn/

# 5. Настройка OpenVPN-сервера
echo -e "${YELLOW}[8/11] Создание символьной ссылки на server.conf...${NC}"
# Удаляем существующий файл/ссылку если есть
rm -f /etc/openvpn/server.conf
# Копируем конфиг из репозитория
cp -f "$SCRIPT_DIR/config/server.conf" /etc/openvpn/server.conf
echo -e "${GREEN}Конфиг сохранен: /etc/openvpn/server.conf"

# 6. Включение IP-маршрутизации
echo -e "${YELLOW}[9/11] Включение IP-маршрутизации...${NC}"
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -p

# 7. Настройка NAT
echo -e "${YELLOW}[10/11] Настройка NAT...${NC}"
# Определяем внешний интерфейс (ищем слово 'dev' в выводе ip route)
EXT_IF=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
if [ -z "$EXT_IF" ]; then
    echo -e "${RED}Не удалось определить внешний интерфейс. Укажите его вручную (например, eth0):${NC}"
    read EXT_IF
fi
echo "Используется внешний интерфейс: $EXT_IF"

iptables -t nat -C POSTROUTING -o "$EXT_IF" -j MASQUERADE >/dev/null 2>&1 || \
iptables -t nat -A POSTROUTING -o "$EXT_IF" -j MASQUERADE
systemctl enable netfilter-persistent
netfilter-persistent save

# 8. Запуск сервиса
echo -e "${YELLOW}[11/11] Запуск сервиса OpenVPN...${NC}"
systemctl enable --now openvpn@server

sleep 3
if systemctl is-active --quiet openvpn@server; then
    echo -e "${GREEN}Сервис OpenVPN успешно запущен!${NC}"
else
    echo -e "${RED}Ошибка при запуске сервиса. Проверьте логи: journalctl -u openvpn@server -n 50${NC}"
fi

# 9. Получение IP-адреса сервера из внешнего интерфейса
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}Настройка завершена. Получение IP-адреса сервера...${NC}"

# Получаем IP-адрес внешнего сетевого интерфейса
SERVER_IP=$(ip -4 addr show "$EXT_IF" | awk '/inet/ {print $2}' | cut -d/ -f1 | head -n 1)

if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}Не удалось получить IP-адрес интерфейса $EXT_IF.${NC}"
    echo -e "${YELLOW}Введите внешний IP сервера вручную:${NC}"
    read SERVER_IP
fi

echo -e "${GREEN}IP-адрес сервера: $SERVER_IP${NC}"

# 10. Генерация клиентского конфигурационного файла
CLIENT_NAME="client"
OVPN_DIR="/root/openvpn-clients"
mkdir -p "$OVPN_DIR"

cd /etc/openvpn/easy-rsa/

# Создаем базовый конфиг с инлайн-сертификатами
cat <<EOF > "$OVPN_DIR/$CLIENT_NAME.ovpn"
client
dev tun
proto tcp
remote $SERVER_IP 31194
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-128-CBC
data-ciphers AES-128-CBC
data-ciphers-fallback AES-128-CBC
auth SHA1
remote-cert-tls server
verb 3

<ca>
$(cat pki/ca.crt)
</ca>

<cert>
$(cat pki/issued/$CLIENT_NAME.crt)
</cert>

<key>
$(cat pki/private/$CLIENT_NAME.key)
</key>
EOF

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}Установка OpenVPN Antizapret успешно завершена!${NC}"
echo -e "${GREEN}Статус сервиса: systemctl status openvpn@server${NC}"
echo -e "${GREEN}Клиентский конфиг сохранен в: $OVPN_DIR/$CLIENT_NAME.ovpn${NC}"
echo -e "${GREEN}Скачайте этот файл на ваше устройство и импортируйте в OpenVPN Connect.${NC}"
echo -e "${GREEN}======================================================================${NC}"
