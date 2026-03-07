# HW04 — Patroni HA (3x etcd, 3x PostgreSQL/Patroni, HAProxy) + pgBackRest (NFS repo)

Домашнее задание: **Высокая доступность: развертывание Patroni**  
Цель: развернуть отказоустойчивый кластер PostgreSQL с Patroni + проверка failover + бэкапы.

---

## 0) Архитектура

### Компоненты

- **etcd (DCS):** 3 ВМ
- **PostgreSQL + Patroni:** 3 ВМ
- **HAProxy:** 1 ВМ (балансировщик)
- **Backup server:** 1 ВМ + отдельный диск **200GB** под репозиторий pgBackRest (экспорт по NFS)

### Сеть и порты

- Patroni REST API: `:8008` (на каждой PG-ноде)
- PostgreSQL: `:5432` (на каждой PG-ноде, управляется Patroni)
- HAProxy:
  - `:5432` → **leader** (writes)
  - `:5433` → **replicas** (reads, round-robin)
  - `:7000` → stats UI
- etcd: `:2379` (client)
- NFS: `:2049` (backup server)

---

## 1) IP-план (как в стенде)

> Если у вас другой стенд — адаптируйте `inventory/group_vars/all.yml`.

- etcd:
  - `etcd-01.prod.home.arpa` → `10.10.92.112`
  - `etcd-02.prod.home.arpa` → `10.10.92.113`
  - `etcd-03.prod.home.arpa` → `10.10.92.114`
- Patroni/PostgreSQL:
  - `pg-01.prod.home.arpa` → `10.10.92.115`
  - `pg-02.prod.home.arpa` → `10.10.92.116`
  - `pg-03.prod.home.arpa` → `10.10.92.117`
- HAProxy:
  - `haproxy-01.prod.home.arpa` → `10.10.92.118`
- Backup server:
  - `backup-01.prod.home.arpa` → `10.10.92.119`

---

## 2) Требования

### На control-host (где запускаем Ansible)

- Python 3 + venv
- Доступ по сети до Proxmox API
- SSH ключ (`~/.ssh/id_ed25519.pub`) — будет прокинут в ВМ через cloud-init
- DNS (или /etc/hosts), чтобы резолвились имена `*.prod.home.arpa`  
  *(в моём стенде DNS через AdGuard `10.10.92.53`)*

### На Proxmox

- Шаблон cloud-init VM с известным `VMID` (например `9100`)
- API token (user/token_id/token_secret)

---

## 3) Как развернуть “из коробки” (создание ВМ + настройка всех ролей)

### 3.1. Подготовка и зависимости

Перейти в каталог с Ansible-проектом и поставить зависимости:

```bash
cd hw04-patroni-ha/ansible
./bootstrap.sh
source .venv/bin/activate
3.2. Переменные окружения (env.sh)

Создайте env.sh (ВАЖНО: не коммитьте токены/пароли в Git):

cat > env.sh <<'EOF'
export PROXMOX_API_HOST='pve01.mgmt.home.arpa'
export PROXMOX_API_USER='ansible@pve'
export PROXMOX_API_TOKEN_ID='semaphore'
export PROXMOX_API_TOKEN_SECRET='REPLACE_ME'

export PROXMOX_NODE='domushnik'
export PROXMOX_STORAGE='hdd-vmdata'
export PROXMOX_TEMPLATE_ID='9100'

export DNS_SERVER='10.10.92.53'
export SEARCH_DOMAIN='prod.home.arpa'

export CI_USER='aurus'
export CI_PASSWORD='Zz12345678'
export CLOUD_INIT_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"

# Размер дополнительного диска на backup-VM (GB)
export BACKUP_DISK_SIZE_GB='200'
EOF

source ./env.sh
3.3. Запуск (полный цикл)
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
4) Повторный прогон без пересоздания ВМ

Если ВМ уже созданы и вы хотите просто “донастроить/переприменить конфиги”:

ansible-playbook -i inventory/hosts.yml playbooks/site.yml -e provision_vms=false
5) Проверка: что всё живо
5.1 etcd (здоровье кластера)

Запускать можно с любой ноды, где есть etcdctl (удобно — на etcd-ноде):

ETCDCTL_API=3 etcdctl \
  --endpoints="http://10.10.92.112:2379,http://10.10.92.113:2379,http://10.10.92.114:2379" \
  endpoint status -w table

ETCDCTL_API=3 etcdctl \
  --endpoints="http://10.10.92.112:2379,http://10.10.92.113:2379,http://10.10.92.114:2379" \
  endpoint health -w table

Ожидаемо: все endpoints отвечают, здоровье true.

5.2 Patroni (leader + replicas)

На любой PG-ноде:

sudo patronictl -c /etc/patroni/patronictl.yml list

Ожидаемо:

1 нода: Role = Leader, State = running

2 ноды: Role = Replica, State = streaming

5.3 HAProxy (маршрутизация writes/reads)

Точки входа для клиентов:

Writes (leader): 10.10.92.118:5432

Reads (replicas): 10.10.92.118:5433

HAProxy stats: http://10.10.92.118:7000/

Проверка через psql (на haproxy-ноде)

Если psql не установлен:

sudo apt update
sudo apt install -y postgresql-client

Далее:

export PGPASSWORD='PostgresPasswordChangeMe'

# leader-only (writes)
for i in {1..6}; do
  psql -h 10.10.92.118 -p 5432 -U postgres -d postgres -tAc \
    "select inet_server_addr(), pg_is_in_recovery();"
done

# replicas rr (reads)
for i in {1..6}; do
  psql -h 10.10.92.118 -p 5433 -U postgres -d postgres -tAc \
    "select inet_server_addr(), pg_is_in_recovery();"
done

Ожидаемо:

5432 всегда один IP и |f

5433 чередует IP реплик и |t

6) Проверка отказоустойчивости (failover)

Цель: имитировать падение master/leader и показать, что:

лидер переключается на другую ноду

HAProxy :5432 начинает вести на нового лидера

кластер остаётся доступным

6.1 Зафиксировать текущего лидера

На любой PG-ноде:

sudo patronictl -c /etc/patroni/patronictl.yml list

Запомнить, кто сейчас Leader (например pg-01).

6.2 Наблюдение за leader через HAProxy (параллельная консоль)

На haproxy-ноде:

export PGPASSWORD='PostgresPasswordChangeMe'
while true; do
  date
  psql -h 10.10.92.118 -p 5432 -U postgres -d postgres -tAc \
    "select inet_server_addr(), pg_is_in_recovery();"
  sleep 1
done

Ожидаемо: постоянно один IP (текущий лидер), |f.

6.3 “Уронить” лидера (2 варианта)
Вариант A (через Proxmox — имитация аварии железа)

В UI/CLI Proxmox: Stop/PowerOff VM лидера (например pg-01).

Вариант B (через systemctl на лидере)

На лидере:

sudo systemctl stop patroni

Подождать ~10–30 секунд.

6.4 Проверить, что лидер сменился

На любой PG-ноде:

sudo patronictl -c /etc/patroni/patronictl.yml list

Ожидаемо: Leader — уже другая нода.

Параллельная консоль “наблюдения” через HAProxy должна показать:

кратковременные ошибки подключения (в момент failover) — это нормально

затем inet_server_addr() сменится на IP нового лидера, |f

6.5 Проверка “кластер реально работает” после failover

После переключения лидера:

export PGPASSWORD='PostgresPasswordChangeMe'
psql -h 10.10.92.118 -p 5432 -U postgres -d postgres -c \
  "create table if not exists ha_check(ts timestamptz default now(), leader inet);
   insert into ha_check(leader) values (inet_server_addr());
   select * from ha_check order by ts desc limit 5;"

Ожидаемо: insert проходит через :5432 и возвращается строка.

6.6 Вернуть упавшую ноду назад

Если вы “стопали” в Proxmox — включить VM обратно.
Если “стопали” patroni — запустить:

sudo systemctl start patroni

И снова проверить:

sudo patronictl -c /etc/patroni/patronictl.yml list

Ожидаемо: нода вернулась как Replica и streaming.

7) Бэкапы (pgBackRest + NFS repo)

Схема:

Backup VM поднимает NFS export репозитория pgBackRest

На backup-VM монтируется отдельный диск 200GB в /srv/pgbackups

Репозиторий доступен как /srv/pgbackups/pgbackrest

На PG-нодах NFS монтируется в /backup/pgbackrest

7.1 Проверка репозитория на PG-ноде (leader)

Узнать лидера:

sudo patronictl -c /etc/patroni/patronictl.yml list

На лидере:

df -h /backup/pgbackrest
mount | grep pgbackrest || true
sudo -u postgres pgbackrest --stanza=pgcluster info

Ожидаемо:

/backup/pgbackrest примонтирован (NFS)

pgbackrest info показывает stanza pgcluster и список backup’ов

7.2 Проверка репозитория на backup server

На backup-01:

df -h /srv/pgbackups
ls -lah /srv/pgbackups/pgbackrest
ls -lah /srv/pgbackups/pgbackrest/backup/pgcluster || true

Ожидаемо: есть директории archive/, backup/, появляются файлы stanza/backup.

7.3 Проверка расписания (systemd timer)

На лидере:

systemctl list-timers --all | grep -i pgbackrest || true
systemctl status pgbackrest-backup.timer --no-pager
journalctl -u pgbackrest-backup.service -n 100 --no-pager
7.4 Принудительный запуск backup (чтобы показать “делается”)

На лидере:

sudo systemctl start pgbackrest-backup.service
sudo -u postgres pgbackrest --stanza=pgcluster info

Ожидаемо: после запуска info покажет свежий backup (или обновлённые таймстампы).

8) Скрины для сдачи (рекомендуемый минимум)

Положить в hw04-patroni-ha/screens/:

01_patronictl_before.png — patronictl list до failover

02_haproxy_5432_before.png — проверка через HAProxy:5432 до

03_failover_action.png — stop VM в Proxmox (или systemctl stop patroni)

04_patronictl_after_failover.png — patronictl list после (новый leader)

05_haproxy_5432_after.png — HAProxy:5432 ведёт на нового лидера

06_haproxy_5433_reads.png — HAProxy:5433 отдаёт реплики (RR)

07_pgbackrest_info.png — pgbackrest info на лидере

08_backup_vm_repo.png — содержимое /srv/pgbackups/pgbackrest на backup-VM

09_pgbackrest_timer.png — list-timers/journalctl на лидере

10_pgbackrest_manual_run.png — принудительный запуск backup + info

9) Мини-отчёт: что сделано и почему это важно

Развёрнут HA-кластер PostgreSQL на базе Patroni с распределённым DCS (etcd) и балансировкой/роутингом (HAProxy).

HAProxy разделяет трафик:

:5432 — всегда на leader (writes)

:5433 — на replicas (reads)

Проверен failover: при падении лидера кластер выбирает нового лидера и HAProxy начинает вести writes на него.

Настроены бэкапы через pgBackRest:

репозиторий на отдельной backup-VM с отдельным диском (200GB)

общий доступ для PG-нод через NFS

автоматический запуск через systemd timer

выполнен первичный full backup и проверено наличие в репозитории

10) Важное про безопасность (чтобы не было “подкопался”)

Не коммитить env.sh (там токены/пароли).

Не хранить токены/пароли в репозитории.

В репо можно хранить env.example.sh без секретов (placeholder’ы).

11) Troubleshooting (коротко)

401 Unauthorized: invalid token value → неправильный PROXMOX_API_TOKEN_SECRET

“Missing required env vars” → не экспортированы переменные (особенно CLOUD_INIT_SSH_PUBLIC_KEY)

psql not found на haproxy → sudo apt install postgresql-client

patronictl не видит etcd → проверь /etc/patroni/patronictl.yml (ендпоинты etcd должны быть 10.10.92.112-114:2379)

pgbackrest permission denied → права на repo (на стенде настроено для lab-режима, но если ужесточать — делайте владельца/группу под postgres)
