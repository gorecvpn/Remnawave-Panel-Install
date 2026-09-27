# 🩹 WTM v1.6.1 — hotfix: установка Tor на Debian/Ubuntu

> Срочная заплатка к v1.6.0. Если вы обновились до 1.6.0 — обновитесь до 1.6.1 **до** того, как ставить Tor.

## Симптом

`sudo wtm install-tor` падал сразу после записи конфига:

```
ℹ️  Configuring Tor...
ℹ️  Previous config backed up to /etc/tor/torrc.backup.20260827-133546
❌ Generated torrc failed Tor's own validation
   [warn] /var/lib/tor is not owned by this user (root, 0) but by debian-tor (110).
   [warn] Failed to parse/validate config: Couldn't access private data directory "/var/lib/tor"
   [err] Reading config failed--see warnings above.
```

## Причина

Виновата новая проверка конфига из 1.6.0, а не сам конфиг. В 1.6.0 перед перезапуском добавился прогон `tor --verify-config`, чтобы не влетать в crash-loop с битым `torrc`. Но запускался он **от root и без файла defaults**, а штатный юнит стартует Tor совсем иначе:

```
ExecStart=/usr/bin/tor --defaults-torrc /usr/share/tor/tor-service-defaults-torrc -f /etc/tor/torrc ...
User=debian-tor
```

Tor сверяет владельца `DataDirectory` с тем пользователем, под которым **собирается работать**. От root, без `--defaults-torrc` (а именно там лежит `User debian-tor`), он видит `/var/lib/tor`, принадлежащий `debian-tor`, и отказывается — хотя конфиг полностью корректен.

Ирония в том, что это ровно та же ошибка, от которой лечит вся версия 1.6.0: проверка воспроизводила не то, как сервис работает на самом деле.

## Что исправлено

* `tor_verify_config()` теперь валидирует так же, как стартует юнит: подхватывает `--defaults-torrc`, если он есть, и при неудаче повторяет проверку с явным `--User`.
* `tor_run_user()` определяет учётку демона из самого юнита (`systemctl show -p User`), с запасным списком `debian-tor` / `toranon` / `tor` — покрывает и Debian/Ubuntu, и RHEL-семейство.
* Если конфиг всё-таки не проходит проверку, **предыдущий `torrc` возвращается из бэкапа** — прерванная установка больше не оставляет систему с отвергнутым конфигом.
* Действительно битый конфиг по-прежнему отбраковывается, с выводом причины от самого Tor.

## Обновление

```bash
sudo wtm self-update
sudo wtm install-tor --force
```

Если установка уже прерывалась на 1.6.0, система осталась в промежуточном состоянии: пакет tor стоит, `torrc` записан, сервис не поднят. `install-tor --force` приводит всё в порядок; ваш прежний конфиг лежит рядом в `torrc.backup.<дата-время>`.

---

# 🌐 WTM v1.6.0 — Tor больше не врёт о своём состоянии

> Привет 👋
>
> Это самое важное обновление WTM за всё время. Коротко: **скрипт больше не верит файлам и кодам возврата — он проверяет факты.**
>
> Повод был неприятный. На боевом сервере Tor лежал мёртвым несколько дней, и никто этого не заметил: `wtm status` бодро показывал `✅ RUNNING`, а `wtm install-tor` отвечал «уже установлен и настроен». Разбор этого случая и стал техзаданием для v1.6.0.

---

## 😱 Что произошло на самом деле

Классическая ловушка systemd, на которую напорется каждый, кто соберёт свой юнит для Tor.

В `/etc/systemd/system/tor.service` был написан руками юнит, перекрывающий пакетный:

```ini
User=debian-tor
ExecStartPre=/usr/bin/install -Z -m 02755 -o debian-tor -g debian-tor -d /run/tor
```

Строка скопирована из штатного `tor@default.service`. Но **`ExecStartPre=` выполняется от `User=`**, а `debian-tor` не может создать каталог в `/run` (root:root 0755):

```
install: cannot change owner and permissions of /run/tor: No such file or directory
```

В пакетном юните рядом стоит `PermissionsStartOnly=yes`, которая заставляет `ExecStartPre` выполняться от root. В копию она не переехала.

Добил `Restart=always` + `RestartSec=5s` при дефолтном `StartLimitBurst=5`/10 s: пять мгновенных падений → `Start request repeated too quickly` → юнит в состоянии `failed` **навсегда**. systemd больше не пытается его поднять. Никогда.

**А WTM в этот момент говорил, что всё хорошо.** Вот это и чинили.

---

## 🔍 Три корневые причины

### 1. Скрипт верил наличию файла, а не состоянию сервиса

Было:

```bash
if [ -f "$TOR_CONFIG_FILE" ]; then
    warn "Tor is already installed and configured"   # даже если он мёртв неделю
```

Стало: проверяется реальное состояние, и вместо отказа запускается ремонт.

### 2. Скрипт управлял не тем юнитом

На Debian/Ubuntu `tor.service` — это **`Type=oneshot` / `ExecStart=/bin/true`**, пустышка-мастер для multi-instance. Настоящий демон живёт в **`tor@default.service`**.

Последствие: `systemctl enable --now tor` возвращает успех, `systemctl is-active tor` отвечает `active` — **при полном отсутствии процесса tor в системе**. Захардкоженный `TOR_SERVICE="tor"` из скрипта удалён совсем; юнит теперь определяется в рантайме.

### 3. Открытый сокет ≠ работающий Tor

Проверка была такой:

```bash
ss -tlnp | grep -q ":9050"     # порт слушается — значит всё хорошо?
```

Порт 9050 открывается почти мгновенно, а сборка цепочек занимает от секунд до минуты. Tor, который слушает, но не забутстрапился (заблокированный ДЦ, нет доступа к directory authorities), светился в меню как `RUNNING ✅ / SOCKS5 ✅`, а весь трафик через него отваливался.

---

## ✨ Что нового

### 🩺 `wtm repair-tor` — починка без переустановки

Одна команда чинит всё, что мешает Tor стартовать, не трогая ваш `torrc`:

```bash
sudo wtm repair-tor
```

* находит и **разбирает самописный юнит**, объясняя человеческим языком, что в нём сломано;
* уносит его в бэкап (`tor.service.wtm-backup.<timestamp>`) — не удаляет;
* снимает `mask` и сбрасывает залипшее состояние `failed`;
* чинит владельца и права каталогов;
* ставит drop-in против start-limit;
* перезапускает и **дожидается реального bootstrap**, а не «сокет открылся».

Доступно и в меню Tor — пункт **11**.

### 🐶 Watchdog для Tor

У WARP watchdog был, у Tor — нет. Именно сценарий «сервис умер и остался лежать» он и ловит.

```bash
sudo wtm tor-watchdog-on
sudo wtm tor-watchdog-off
```

Cron каждые 5 минут. Мёртвый юнит или закрытый порт — рестарт сразу. Провал проверки цепочки — только после **двух подряд**, чтобы сетевой блип не дёргал живой Tor. Перед рестартом делает `reset-failed`, иначе юнит, упёршийся в start-limit, не поднимется никакими рестартами.

Включается автоматически при установке Tor. Если не нужно — `WTM_NO_WATCHDOG=true` перед командой.

### ✅ Строка `Circuit:` в статусе

Второй уровень проверки: реальный запрос через SOCKS до `check.torproject.org/api/ip` с разбором `"IsTor":true`.

```
🧅 Tor Status:
✅ RUNNING
   Memory:      42MB
   SOCKS5:      ✅ 127.0.0.1:9050
   Control:     ✅ 127.0.0.1:9051
   Circuit:     ✅ Verified via Tor
   Watchdog:    ✅ Enabled (cron */5)
```

Проверка **не тормозит меню**: отдаёт кэш (TTL 60 с) и обновляется в фоне, первый рендер показывает `⏳ checking`.

### ❌ Новое состояние `BROKEN`

Раньше «остановлен админом» и «сломан неделю назад» выглядели одинаково. Теперь — нет:

```
🧅 Tor Status:
❌ INSTALLED BUT BROKEN
   Unit:        tor@default (failed)
   Unit is in the failed state
   Shadowed by a hand-written unit: /etc/systemd/system/tor.service
   Fix it with: wtm repair-tor
```

### 🌐 `--dns-port` — DNS через Tor

```bash
sudo wtm install-tor --dns-port 5353
```

Добавляет `DNSPort` + `AutomapHostsOnResolve` (то, что делает `.onion` резолвящимися). Главное: **при `install-tor --force` уже настроенный `DNSPort` наследуется автоматически** — переустановка больше не может молча уронить Xray, у которого DNS смотрит на `127.0.0.1:5353`.

### 🔄 `wtm new-identity` — теперь по-настоящему

Пункт «Regenerate identity» раньше делал `systemctl reload`, то есть SIGHUP = перечитать конфиг. **Личность при этом не менялась.** Теперь это честный `SIGNAL NEWNYM` через control-порт, с password- и cookie-аутентификацией.

```bash
sudo wtm new-identity
```

---

## 🐛 Исправлено

* **`uninstall_tor` никогда не удалял пакет.** `remove_tor` не вызывал `detect_os`, поэтому `case $OS` проваливался вхолостую. Плюс теперь снимаются маски, чистится drop-in, убирается чужой юнит — следующая установка не унаследует поломку.
* **`install-tor --force` падал с «порты недоступны»**, потому что 9050 занят самим Tor. Теперь сокеты, принадлежащие процессу `tor`, исключаются (разбирается вывод и `ss`, и `netstat`).
* **Занятый порт убивал всё меню:** там был `error_exit`, то есть `exit 1` из интерактивного режима.
* **Бэкап `torrc` делался только один раз.** Вторая переустановка молча съедала правки. Теперь `torrc.backup.<дата-время>`, хранятся 5 последних.
* **Утечка DNS в тестах.** В `test_connections` использовался `--socks5` вместо `--socks5-hostname` — имена резолвились локально, мимо Tor, плюс ложное «Connection failed» на хостах со сломанным `resolv.conf`. Заменено везде, включая все примеры в справке.
* **`wtm logs tor` показывал пустоту.** `torrc` писал `Log notice file`, а команда следила за journalctl. Теперь в конфиг добавлен `Log notice stdout`, а `show_logs` сам выбирает живой источник. И логи показываются, **когда сервис лежит** — раньше скрипт отказывался их показать именно тогда, когда они нужны.
* **Ложный успех по старому логу.** Определение bootstrap привязано к `ActiveEnterTimestamp` юнита, так что `Bootstrapped 100%` от прошлого запуска не засчитывается.
* **Проверка обновлений предлагала откат.** Сравнение версий было строковым `!=`, а не «новее»: сборка 1.6.0 при 1.5.1 в репозитории получала «🆙 New version available: 1.5.1» — и `self-update` этот даунгрейд **выполнял**. Добавлено нормальное сравнение; откат теперь только явным `self-update --force`.
* **Автоустановка затирала свежую версию.** Запуск локального файла на сервере ставил в `/usr/local/bin/wtm` older-версию с GitHub. Теперь, если запущенный файл новее опубликованного, ставится он.

---

## ⚠️ Изменения в поведении

Ломающих изменений нет, но кое-что теперь работает иначе — и это осознанно:

| Что | Было | Стало |
|-----|------|-------|
| `start-tor` / `restart-tor` | мгновенный «✅ started» | ждёт реального bootstrap (до 90 с) |
| `install-tor` на сломанном Tor | «уже установлен», выход | автоматический ремонт |
| `install-tor` | — | включает watchdog (`WTM_NO_WATCHDOG=true` отключает) |
| Счётчик в `wtm test` | Tor засчитан, если порт открыт | засчитан, только если трафик реально идёт через Tor |
| `torrc` | `Log notice file` | плюс `Log notice stdout` |

---

## 📦 Как обновиться

```bash
sudo wtm self-update
```

Или, если WTM ещё не установлен:

```bash
sudo bash <(curl -sL https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/wtm.sh) @ install-script
```

Если Tor уже стоит и ведёт себя странно — первым делом:

```bash
sudo wtm repair-tor
sudo wtm test
```

---

## 📋 Новые команды v1.6.0

```bash
sudo wtm repair-tor                     # починить сломанный юнит Tor
sudo wtm tor-watchdog-on                # включить watchdog для Tor
sudo wtm tor-watchdog-off               # выключить
sudo wtm new-identity                   # новые цепочки (настоящий NEWNYM)
sudo wtm install-tor --dns-port 5353    # Tor с DNSPort
sudo wtm self-update --force            # откат на опубликованную версию
```

Алиасы: `fix-tor`, `newnym`, `warp-watchdog-on/off`.

---

## 💬 Итог

Главная мысль обновления простая: **инструмент, который врёт о состоянии сервиса, хуже, чем отсутствие инструмента.** Если WTM показывает `✅` — теперь это значит, что через Tor реально прошёл запрос, а не что где-то открыт сокет.

Буду рад отзывам и баг-репортам! ⭐ на GitHub тоже приветствуется.

---
---

# 📚 Архив: анонс версии v1.2.1

# 🌐 WTM - WARP & Tor Manager v1.2.1 - Профессиональное управление анонимными сетями

> Привет👋
> 
> Представляю вам **WTM (WARP & Tor Manager)** - современный инструмент для автоматизации установки и управления **Cloudflare WARP** и **Tor** на Linux серверах.
>
> 🆕 **Версия v1.2.1** включает революционную систему автообновления, интерактивные меню и профессиональную диагностику сетевых подключений!

![wtm-banner|690x470](upload://remnawave-script.webp)

## 🎯 Что такое WTM?

**WTM** - это комплексный bash-скрипт корпоративного уровня для управления анонимными сетевыми подключениями. Идеально подходит для настройки прокси-серверов, обхода блокировок и обеспечения приватности в production-окружении.

### 🚀 Cloudflare WARP - Скорость и надежность
* **Автоматическая установка WireGuard** с оптимизированными настройками
* **Интеграция с wgcf** для генерации конфигураций WARP
* **IPv6 поддержка** с автоматическим определением
* **Проверка подключения** через Cloudflare trace API
* **Управление сервисом** через systemctl

### 🧅 Tor Network - Максимальная анонимность
* **Оптимизированная конфигурация** для production-использования
* **SOCKS5 прокси** на порту 9050
* **Control Port** для программного управления
* **Автоматическая ротация** цепочек для безопасности
* **Логирование и мониторинг** подключений

## 💾 Система автообновления - Главная особенность

Особенно горжусь встроенной системой обновлений, реализованной по образцу других скриптов коллекции:

**🔄 Умная система версионирования:**
* **Автоматическая проверка** новых версий при запуске интерактивного режима
* **Безопасное обновление** с проверкой целостности файлов
* **Глобальная установка** в `/usr/local/bin/wtm` для системного доступа
* **Откат изменений** при неудачном обновлении

```bash
# Проверка текущей версии
wtm version                          # Полная информация о версии

# Проверка обновлений
wtm check-updates                    # Сравнение с GitHub

# Автоматическое обновление
sudo wtm self-update                 # Обновление до последней версии
sudo wtm update                      # Альтернативная команда
```

**Новые возможности v1.2.1:**
* **Единый URL обновлений** - совместимость с репозиторием remnawave-scripts
* **Проверка прав доступа** - требование root для обновления
* **Версионная совместимость** - автоматическая миграция конфигураций
* **Интерактивное меню обновлений** - пункт 9 в главном меню

## 📦 Быстрая установка и настройка

Всего одна команда для глобальной установки:

```bash
# Установка как глобальная команда
sudo bash <(curl -sL https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/wtm.sh) @ install-script

# Или прямой запуск
bash <(curl -sL https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/wtm.sh)
```

### 🎯 Умная автоматическая установка

**Новинка v1.2.1:** WTM теперь автоматически устанавливается как глобальная команда при любой операции установки:

```bash
# Любая из этих команд автоматически установит wtm глобально
sudo bash <(curl -sL https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/wtm.sh) install-warp
sudo bash <(curl -sL https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/wtm.sh) install-all
# После этого просто используйте: wtm command
```

**Преимущества автоматической установки:**

* 🚀 **Мгновенный доступ** - команда `wtm` доступна сразу после установки
* 🔄 **Нет дублирования** - умная система предотвращает повторные установки
* 💾 **Безопасность** - установка только при необходимости
* 📱 **Удобство** - работает как в интерактивном, так и в командном режиме

## 🛠️ Комплексное управление сервисами

### 📡 WARP Management
```bash
# Установка и настройка
sudo wtm install-warp               # Обычная установка
sudo wtm install-warp-force         # Принудительная переустановка

# Управление сервисом
sudo wtm start-warp                 # Запуск WARP
sudo wtm stop-warp                  # Остановка
sudo wtm restart-warp               # Перезапуск

# Мониторинг
sudo wtm logs-warp                  # Просмотр логов в реальном времени
```

### 🧅 Tor Management
```bash
# Установка с оптимизацией
sudo wtm install-tor                # Установка с конфигурацией production
sudo wtm install-tor-force          # Переустановка

# Контроль сервиса
sudo wtm start-tor                  # Запуск Tor
sudo wtm stop-tor                   # Остановка
sudo wtm restart-tor                # Перезапуск

# Диагностика
sudo wtm logs-tor                   # Лог-файлы Tor
```

### 🔄 Быстрые действия
```bash
# Массовые операции
sudo wtm install-all                # Установка WARP + Tor
sudo wtm install-all-force          # Принудительная переустановка всего

# Универсальные команды
sudo wtm status                     # Статус всех сервисов
sudo wtm test                       # Тестирование подключений
sudo wtm system-info                # Информация о системе
```

## 📊 Продвинутая диагностика и мониторинг

Встроенные инструменты для production-мониторинга:

### 🔍 Автоматическое тестирование
```bash
# Комплексное тестирование подключений
sudo wtm test

# Результат включает:
├── 🌐 Прямое подключение (проверка базового интернета)
├── 📡 WARP тестирование
│   ├── WireGuard интерфейс (wg show warp)
│   ├── Cloudflare trace (warp=on/plus проверка)
│   └── Сравнение IP адресов
└── 🧅 Tor тестирование
    ├── SOCKS5 порт 9050 (доступность)
    ├── Tor Project verification
    └── Анонимизация IP
```

### 📈 Системный мониторинг
```bash
# Подробная информация о состоянии
sudo wtm status

# Отображает:
├── 💾 RAM usage и публичный IP
├── 📡 WARP статус
│   ├── Состояние сервиса (активен/остановлен)
│   ├── Потребление памяти
│   ├── WireGuard endpoint информация
│   └── Cloudflare verification
└── 🧅 Tor статус
    ├── Статус демона
    ├── SOCKS5 доступность (127.0.0.1:9050)
    ├── Control port (127.0.0.1:9051)
    └── Потребление ресурсов
```

## 🎨 Интерактивное меню - Профессиональный интерфейс

### 🖥️ Главное меню
```
🌐 WARP & Tor Manager v1.2.1
──────────────────────────────────────────────────

🛠️  Service Management:
   1) 📡 WARP Menu
   2) 🧅 Tor Menu  
   3) 🔄 Quick Actions

📊 Monitoring & Tools:
   4) 🧪 Test Connections
   5) 📋 View Logs
   6) 💻 System Information

📖 Configuration:
   7) ⚙️  XRay Configuration
   8) ❓ Help & Usage Examples
   9) 🔄 Check Updates        # ← НОВОЕ в v1.2.1

   0) 🚪 Exit
```

### 🎯 Умные подсказки
Контекстные советы в зависимости от состояния системы:
* **Новая установка**: "Start with WARP Menu (1) or Tor Menu (2)"
* **Активные сервисы**: "Test connections (4) to verify everything works"
* **Частично настроенная**: "Use service menus to start installed components"

## 🔧 XRay Integration - Для продвинутых пользователей

### 📝 Готовые конфигурации
Встроенные примеры для Reality:

```json
{
  "inbounds": [
    
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "socks",
      "settings": {
        "servers": [{"address": "127.0.0.1", "port": 9050}]
      },
      "tag": "tor"
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "VTR-USA"
        ]
        "type": "field",
        "domain": ["regexp:.*\\.onion$"],
        "outboundTag": "tor"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": [
          "VTR-USA",
          "VTR-LT",
          "VTR-NL",
          "to-foreign-inbound"
        ],
        "outboundTag": "warp",
        "domain": [
          "geosite:category-ads-all",
          "geosite:google",
          "geosite:cloudflare",
          "geosite:youtube",
          "geosite:netflix"
        ]
      },
    ]
  }
}
```

### 🔀 Маршрутизация трафика
* **Автоматическая маршрутизация** .onion доменов через Tor
* **Прямое подключение** для обычного трафика
* **WARP integration** для обхода блокировок

## 🌟 Production-готовность

### 🏗️ Системные требования
* **Операционные системы**: Ubuntu, Debian, CentOS, AlmaLinux, Fedora, Arch Linux
* **Архитектуры**: x86_64, ARM64, ARM32 (автоопределение)
* **Права доступа**: Root требуется для установки и управления сервисами
* **Сетевые порты**: 9050, 9051 (Tor) должны быть свободны

### 🔒 Безопасность и стабильность
* **Автоматическое управление DNS** с восстановлением
* **Проверка портов** перед установкой сервисов
* **Backup конфигураций** при изменениях
* **Валидация IPv6** поддержки
* **Временные DNS** для надежной установки

### 📈 Оптимизация производительности
```bash
# Tor оптимизации в конфигурации
ConnLimit 1000                      # Увеличенный лимит подключений
MaxClientCircuitsPending 48         # Больше цепочек для клиентов
NewCircuitPeriod 30                 # Быстрая ротация цепочек
MaxCircuitDirtiness 600             # Время жизни цепочки

# WARP настройки
Table = off                         # Отключение таблицы маршрутизации
PersistentKeepalive = 25           # Поддержание соединения
```

## 📱 Команды одной строкой

### 🔥 Quick Start
```bash
# Быстрый старт для новичков
curl -sL https://github.com/gorecvpn/Remnawave-Panel-Install/raw/main/wtm.sh | sudo bash -s install-all

# Проверка работоспособности
wtm test

# Получение справки
wtm help
wtm usage-examples
```

### ⚡ Power User Commands
```bash
# Мониторинг в одной строке
watch -n 5 'wtm status | grep -A 20 "Network Status"'

# Логи в реальном времени
tmux new-session -d 'wtm logs-warp' \; split-window 'wtm logs-tor' \; attach

# Экспорт конфигураций
sudo cp /etc/wireguard/warp.conf /backup/
sudo cp /etc/tor/torrc /backup/
```

## 🔗 Ресурсы и поддержка

* **GitHub Repository**: [https://github.com/gorecvpn/Remnawave-Panel-Install](https://github.com/gorecvpn/Remnawave-Panel-Install)
* **WTM Documentation**: Полная документация в README-warp.md
* **Issue Tracker**: Приветствуются баг-репорты и предложения
* **Project Website**: [https://gig.ovh](https://gig.ovh)

### 🎓 Обучающие материалы
* **XRay конфигурации** с примерами Reality + Tor
* **Тестовые команды** для проверки анонимности  

---

## 🎉 Заключение

✅ **Простота**: Установка в одну команду, интуитивное меню  
✅ **Надежность**: Production-tested, автоматическое восстановление  
✅ **Актуальность**: Система автообновлений, активная разработка  
✅ **Гибкость**: От домашнего использования до enterprise-решений  
✅ **Интеграция**: Часть экосистемы remnawave-scripts  

Буду рад отзывам и предложениям! Если WTM оказался полезным - поставьте ⭐ на GitHub!