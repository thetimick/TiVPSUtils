# TiVPSUtils

Набор утилит для настройки и администрирования VPS.

## Установка

Установить TiVPSUtils одной командой:

```bash
curl -fsSL https://raw.githubusercontent.com/thetimick/TiVPSUtils/main/install.sh | sudo bash && source /etc/profile.d/tivpsutils.sh
```

После установки будут доступны команды TiVPSUtils:

```bash
tiinstall
tiupdate
tif2b
```

## Структура утилит

`src/f2b.sh` и `src/update.sh` содержат меню и точки входа.
Общее оформление консоли, сообщения, подтверждения и проверка root-прав
находятся в `src/helpers/ui.sh`. Функции управления Fail2ban и
автообновлениями находятся в `src/helpers/f2b.sh` и `src/helpers/update.sh`.
Хелперы подключаются относительно пути скрипта; запускайте утилиты вместе
с каталогом `helpers`. Они не создают отдельных aliases.
Цвета отключаются при перенаправлении вывода, `TERM=dumb` или `NO_COLOR=1`.

Для повторного запуска менеджера установки:

```bash
tiinstall
```
