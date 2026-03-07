# HW04 — Patroni HA (3x etcd, 3x PostgreSQL/Patroni, HAProxy) + pgBackRest

## Архитектура
- etcd: 3 VM (DCS)
- PostgreSQL/Patroni: 3 VM
- HAProxy: 1 VM
- Backup server: 1 VM (NFS repo для pgBackRest + отдельный диск 200G)

## Точки входа
- Writes (leader): `10.10.92.118:5432`
- Reads (replicas): `10.10.92.118:5433`
- HAProxy stats: `http://10.10.92.118:7000/`

## Запуск
```bash
cd hw04-patroni-ha/ansible
./bootstrap.sh
source .venv/bin/activate

# Создай env.sh локально (НЕ коммить!)
# Можно взять за основу env.example.sh
source ./env.sh

ansible-playbook -i inventory/hosts.yml playbooks/site.yml

Повторный прогон без пересоздания ВМ:

ansible-playbook -i inventory/hosts.yml playbooks/site.yml -e provision_vms=false
Проверка Patroni / HAProxy

Leader/replicas:

sudo patronictl -c /etc/patroni/patroni.yml list

Проверка через HAProxy:

export PGPASSWORD='PostgresPasswordChangeMe'
psql -h 10.10.92.118 -p 5432 -U postgres -d postgres -tAc "select inet_server_addr(), pg_is_in_recovery();"
psql -h 10.10.92.118 -p 5433 -U postgres -d postgres -tAc "select inet_server_addr(), pg_is_in_recovery();"
Failover тест

Смотрим leader:

sudo patronictl -c /etc/patroni/patroni.yml list

На leader:

sudo systemctl stop patroni

Через 10–30 сек снова list — leader должен смениться.

Бэкапы (pgBackRest)

На leader:

sudo -u postgres pgbackrest --stanza=pgcluster info
systemctl list-timers --all | grep -i pgbackrest || true

На backup server:

df -h /srv/pgbackups
ls -la /srv/pgbackups/pgbackrest

