#!/bin/bash

# --- НАСТРОЙКИ ---
# Домашняя директория
HOME_DIR="/opt/ovpn-scripts"
# Путь к директории easy-rsa (измените при необходимости)
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
# Путь к шаблону клиентского конфига (создайте его заранее, см. ниже)
CLIENT_TEMPLATE="$HOME_DIR/client.template.ovpn"
# Директория, куда сохранять готовые .ovpn файлы
OUTPUT_DIR="$HOME_DIR/clients"

CLIENT_NAME=$1

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите скрипт от имени root (sudo)${NC}"
  exit 1
fi

# Переход в директорию easy-rsa
cd "$EASY_RSA_DIR" || { echo -e "${RED}Не удалось перейти в $EASY_RSA_DIR${NC}"; exit 1; }

# Проверка существования шаблона
if [ ! -f "$CLIENT_TEMPLATE" ]; then
  echo -e "${RED}Ошибка: Файл шаблона $CLIENT_TEMPLATE не найден.${NC}"
  echo "Создайте файл client.template.ovpn с базовыми настройками (без ключей)."
  exit 1
fi

# Ввод имени клиента
#read -p "Введите имя клиента (например, user1): " CLIENT_NAME

if [ -z "$CLIENT_NAME" ]; then
  echo -e "${RED}Имя клиента не может быть пустым.${NC}"
  exit 1
fi

# Проверка, не занято ли имя
if [ -f "pki/issued/${CLIENT_NAME}.crt" ]; then
  read -p "Клиент '$CLIENT_NAME' уже существует. Пересоздать? (y/n): " CONFIRM
  if [ "$CONFIRM" != "y" ]; then
    echo "Отмена."
    exit 0
  fi
  # Отзыв старого сертификата (опционально, можно удалить)
 # echo "Отзыв старого сертификата..."
 # ./easyrsa revoke "$CLIENT_NAME"
 # ./easyrsa gen-crl
fi

echo -e "${GREEN}Генерация запроса и ключа для $CLIENT_NAME...${NC}"
# Генерируем ключ и запрос на подпись (без пароля для удобства, nopass)
EASYRSA_BATCH=1 ./easyrsa build-client-full "$CLIENT_NAME" nopass

if [ $? -ne 0 ]; then
  echo -e "${RED}Ошибка при генерации сертификата.${NC}"
  exit 1
fi

echo -e "${GREEN}Сертификат успешно создан.${NC}"

# Создаем директорию для вывода, если нет
mkdir -p "$OUTPUT_DIR"

# Формируем итоговый .ovpn файл
OUTPUT_FILE="$OUTPUT_DIR/${CLIENT_NAME}.ovpn"

echo "Сборка файла $OUTPUT_FILE..."

# Читаем шаблон и заменяем плейсхолдеры на содержимое файлов
{
  cat "$CLIENT_TEMPLATE"

  echo "<ca>"
  cat pki/ca.crt
  echo "</ca>"

  echo "<cert>"
  cat pki/issued/${CLIENT_NAME}.crt
  echo "</cert>"

  echo "<key>"
  cat pki/private/${CLIENT_NAME}.key
  echo "</key>"

} > "$OUTPUT_FILE"

# Установка правильных прав доступа
chmod 600 "$OUTPUT_FILE"

echo -e "${GREEN}Готово! Файл сохранен здесь: ${OUTPUT_FILE}${NC}"
echo "Вы можете скачать его и использовать в клиенте OpenVPN."
