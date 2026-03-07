# Мини-отчёт: HA PostgreSQL на Patroni

## 0. Исходные данные

- Цель: отказоустойчивый кластер PostgreSQL на Patroni
- Состав:
  - 3× etcd (DCS)
  - 3× Patroni + PostgreSQL
  - 1× HAProxy
  - 1× Backup (NFS repo + pgBackRest)

Таблица узлов (пример):

| Роль | Hostname | IP | Порт(ы) |
|---|---|---:|---|
| etcd | etcd-01 | 10.10.92.112 | 2379/2380 |
| etcd | etcd-02 | 10.10.92.113 | 2379/2380 |
| etcd | etcd-03 | 10.10.92.114 | 2379/2380 |
| patroni | pg-01 | 10.10.92.115 | 5432 + 8008 |
| patroni | pg-02 | 10.10.92.116 | 5432 + 8008 |
| patroni | pg-03 | 10.10.92.117 | 5432 + 8008 |
| haproxy | haproxy-01 | 10.10.92.118 | 5432/5433/7000 |
| backup | backup-01 | 10.10.92.119 | NFS (/srv/pgbackups) |

---

## 1. Создание виртуальных машин

**Что делал:**

- Подготовил template VM в Proxmox с cloud-init.
- Запустил Ansible-playbook для клонирования 7 ВМ и настройки статических IP через cloud-init.

**Команды:**

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

**Результат:**

- Все 7 ВМ созданы и доступны по SSH.

---

## 2. Развёртывание etcd-кластера

**Что делал:**

- Установил etcd-server/etcd-client на 3 ноды.
- Сконфигурировал initial-cluster (3 ноды), peer/client URLs.
- Запустил сервис etcd.

**Проверка:**

```bash
ETCDCTL_API=3 etcdctl \
  --endpoints="http://10.10.92.112:2379,http://10.10.92.113:2379,http://10.10.92.114:2379" \
  endpoint status -w table

ETCDCTL_API=3 etcdctl \
  --endpoints="http://10.10.92.112:2379,http://10.10.92.113:2379,http://10.10.92.114:2379" \
  endpoint health -w table
```

**Ожидаемый результат:**

- 3 endpoints healthy.

---

## 3. Развёртывание Patroni + PostgreSQL

**Что делал:**

- Установил PostgreSQL и Patroni на 3 ноды.
- Указал DCS (etcd) как источник консенсуса.
- Запустил Patroni на всех нодах.

**Проверка:**

```bash
sudo patronictl -c /etc/patroni/patronictl.yml list
sudo patronictl -c /etc/patroni/patronictl.yml topology
```

**Ожидаемый результат:**

- Один узел в состоянии Leader, остальные — Replica (streaming).

---

## 4. Настройка HAProxy

**Что делал:**

- Установил HAProxy на отдельную ВМ.
- Настроил health-check через Patroni REST API (порт 8008):
  - `:5432` → лидер (`/primary`)
  - `:5433` → реплики (`/replica`)

**Проверка:**

- stats UI: `http://10.10.92.118:7000/`

---

## 5. Тест отказоустойчивости (failover)

**Сценарий:**

1) Определил leader:

```bash
sudo patronictl -c /etc/patroni/patronictl.yml list
```

2) На leader остановил Patroni:

```bash
sudo systemctl stop patroni
```

3) Проверил, что произошёл failover:

```bash
sudo patronictl -c /etc/patroni/patronictl.yml list
```

4) Вернул ноду обратно:

```bash
sudo systemctl start patroni
```

**Ожидаемый результат:**

- Leader сменился на одну из реплик, кластер продолжает работать.

---

## 6. Бэкапы (pgBackRest)

**Что делал:**

- Создал отдельную VM `backup-01` с дополнительным диском (200GB), смонтировал в `/srv/pgbackups`.
- Настроил NFS экспорт `/srv/pgbackups` только для PG-нод.
- На PG-нодах смонтировал NFS в `/backup`.
- Установил pgBackRest, настроил репозиторий `repo1-path=/backup/pgbackrest`.
- В Patroni конфиг добавил `archive_command`/`restore_command` для pgBackRest.
- На leader выполнил `stanza-create` и первый `backup`.

**Проверка:**

```bash
sudo -u postgres pgbackrest --stanza=pgcluster info
sudo -u postgres pgbackrest --stanza=pgcluster check
```

**Автоматизация:**

На всех PG нодах включён systemd timer `pgbackrest-backup.timer`, но реально бэкап запускается только на leader.

---

## 7. Проблемы и решения

- **Проблема:** …
- **Решение:** …

---

## Итог

Кластер Patroni + etcd + HAProxy развернут, проверена отказоустойчивость, доступ к БД не теряется при падении одной ноды.
