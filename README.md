# Инструкция по установке и настройке OpenVPN-сервера на Linux

## 1. Установка необходимых пакетов

Установите OpenVPN и Easy-RSA:

```bash
apt update
apt install -y openvpn iptables-persistent
```

Скопируйте шаблон Easy-RSA в каталог OpenVPN:

```bash
cp -R /usr/share/easy-rsa /etc/openvpn
cd /etc/openvpn/easy-rsa/
```

Создайте файл конфигурации Easy-RSA:

```bash
cp vars.example vars
vim vars
```

Укажите параметры криптографии в файле vars:

```bash
set_var EASYRSA_KEY_SIZE        2048
set_var EASYRSA_ALGO            rsa
```

Сохраните изменения.

---

## 2. Инициализация инфраструктуры открытых ключей (PKI)

Создайте символьную ссылку на конфигурацию OpenSSL:

```bash
ln -s openssl-easyrsa.cnf openssl.cnf
```

Инициализируйте PKI:

```bash
./easyrsa init-pki
```

Создайте корневой центр сертификации (CA):

```bash
./easyrsa build-ca nopass
```

Во время выполнения команды потребуется указать Common Name для центра сертификации, например:

```text
OpenVPN-CA
```

---

## 3. Создание сертификата сервера

Сгенерируйте сертификат и ключ сервера:

```bash
./easyrsa build-server-full server nopass
```

---

## 4. Создание сертификата клиента

Создайте сертификат и ключ клиента:

```bash
./easyrsa build-client-full client nopass
```

При необходимости для каждого пользователя создаётся отдельный сертификат:

```bash
./easyrsa build-client-full user1 nopass
./easyrsa build-client-full user2 nopass
```

---

## 5. Генерация параметров Диффи — Хеллмана

Создайте параметры DH:

```bash
openssl dhparam -out /etc/openvpn/dh.pem 2048
```

Процесс может занять несколько минут.

---

## 6. Копирование сертификатов сервера

Скопируйте необходимые файлы в каталог OpenVPN:

```bash
cp pki/ca.crt /etc/openvpn/
cp pki/issued/server.crt /etc/openvpn/
cp pki/private/server.key /etc/openvpn/
```

---

## 7. Настройка OpenVPN-сервера

Скопируйте файл server.conf из данного проекта в `/etc/openvpn/server.conf`:

---

## 8. Включение IP-маршрутизации

Разрешите пересылку пакетов между интерфейсами:

```bash
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p
```

Проверьте результат:

```bash
sysctl net.ipv4.ip_forward
```

Ожидаемое значение:

```text
net.ipv4.ip_forward = 1
```

---

## 9. Настройка NAT

Для обеспечения доступа VPN-клиентов в интернет настройте маскарадинг.

Предполагается, что внешний интерфейс сервера называется `eth0`:

```bash
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

Для сохранения правил:

```bash
netfilter-persistent save
```

---

## 10. Запуск сервиса

Включите автозапуск и запуск OpenVPN:

```bash
systemctl enable --now openvpn@server
```

Проверьте состояние:

```bash
systemctl status openvpn@server
```

Ожидаемый результат:

```text
Active: active (running)
```

---

## 12. Проверка подключения

Просмотр подключённых клиентов:

```bash
cat /var/log/openvpn-status.log
```

Просмотр журнала OpenVPN:

```bash
journalctl -u openvpn@server -f
```
