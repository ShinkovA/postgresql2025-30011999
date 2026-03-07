# Домашнее задание: Высокая доступность — Patroni + etcd + HAProxy ("из коробки")

Этот архив разворачивает в **Proxmox**:

- **3 ВМ для etcd** (DCS)
- **3 ВМ для PostgreSQL + Patroni**
- **1 ВМ для HAProxy** (балансировка и "умный" роутинг на leader/replica)
- **1 ВМ для Backup** (NFS repo + pgBackRest)

Дальше Ansible:

1) собирает кластер **etcd (3 ноды)**,
2) поднимает **Patroni-кластер PostgreSQL (3 ноды)**,
3) настраивает **HAProxy**:
   - `:5432` → только **leader** (запись)
   - `:5433` → **реплики** (чтение, round-robin)
   - `:7000` → stats UI

IP/VMID уже проставлены под твой диапазон `10.10.92.112-10.10.92.119` в `inventory/group_vars/all.yml`.

Бэкапы:
- на `backup-01` добавляется доп. диск (**по умолчанию 200GB**) и экспортируется NFS `/srv/pgbackups`
- PG-ноды монтируют NFS в `/backup` и используют **pgBackRest**

---

## Требования

- Ansible на control-host
- доступ к Proxmox API по токену
- шаблон VM (cloud-init) в Proxmox
- SSH ключ, который будет прокинут в ВМ (cloud-init)

---

## Переменные окружения (control-host)

Playbook `playbooks/create_infra_vms.yml` читает:

Proxmox API:

- `PROXMOX_API_HOST` **или** `PROXMOX_API_URL`
  - если задан только `PROXMOX_API_HOST`, URL будет собран автоматически как `https://<host>:8006/api2/json`
- `PROXMOX_API_USER` — например `ansible@pve`
- `PROXMOX_API_TOKEN_ID` — например `semaphore`
- `PROXMOX_API_TOKEN_SECRET` — секрет токена

Proxmox clone settings:

- `PROXMOX_NODE` — нода Proxmox (например `domushnik`)
- `PROXMOX_STORAGE` — storage (например `hdd-vmdata`)
- `PROXMOX_BACKUP_STORAGE` — (опционально) storage **только** для доп. диска backup-01 (по умолчанию = `PROXMOX_STORAGE`)
- `PROXMOX_TEMPLATE_ID` — VMID cloud-init шаблона (например `9100`)

Cloud-init:

- `CI_USER`, `CI_PASSWORD` — пользователь/пароль внутри ВМ
- `DNS_SERVER`, `SEARCH_DOMAIN` — DNS/домен для cloud-init
- `CLOUD_INIT_SSH_PUBLIC_KEY` — публичный ключ (одной строкой)

Backups:

- `BACKUP_DISK_SIZE_GB` — размер доп. диска для backup-01 (по умолчанию 200)

⚠️ Важно: **не** используем `!` в переменных (чтобы не ловить bash history expansion).

---

## Установка зависимостей

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install ansible
ansible-galaxy install -r requirements.yml
```

---

## Запуск (полный цикл)

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml
```

---

## Проверка

### etcd

```bash
ETCDCTL_API=3 etcdctl \
  --endpoints="http://10.10.92.112:2379,http://10.10.92.113:2379,http://10.10.92.114:2379" \
  endpoint status -w table

ETCDCTL_API=3 etcdctl \
  --endpoints="http://10.10.92.112:2379,http://10.10.92.113:2379,http://10.10.92.114:2379" \
  endpoint health -w table
```

### Patroni

```bash
sudo patronictl -c /etc/patroni/patronictl.yml list
sudo patronictl -c /etc/patroni/patronictl.yml topology
```

### HAProxy

- запись (leader): `10.10.92.118:5432`
- чтение (replicas): `10.10.92.118:5433`
- stats: `http://10.10.92.118:7000/`

### pgBackRest

Проверить репозиторий/бэкапы на leader:

```bash
sudo -u postgres pgbackrest --stanza=pgcluster info
sudo -u postgres pgbackrest --stanza=pgcluster check
```

На всех PG нодах включён systemd timer `pgbackrest-backup.timer`, но реально бэкап запускается только на leader (скрипт проверяет `/primary`).

---

## Тест отказоустойчивости (ручной сценарий для отчёта)

1) Узнать текущего leader:

```bash
sudo patronictl -c /etc/patroni/patronictl.yml list
```

2) На leader-нODE выполнить:

```bash
sudo systemctl stop patroni
```

3) Подождать 10–30 секунд и снова проверить:

```bash
sudo patronictl -c /etc/patroni/patronictl.yml list
```

4) Запустить Patroni обратно на упавшей ноде:

```bash
sudo systemctl start patroni
```

---

## Мини-отчёт

В архиве есть шаблон отчёта: `REPORT.md` — можно заполнить и сдать.


## Environment variables

Export variables (examples):

```bash
export PROXMOX_API_HOST='pve01.mgmt.home.arpa'
export PROXMOX_API_USER='ansible@pve'
export PROXMOX_API_TOKEN_ID='semaphore'
export PROXMOX_API_TOKEN_SECRET='<token-secret>'
export PROXMOX_NODE='domushnik'
export PROXMOX_STORAGE='hdd-vmdata'
# optional: separate storage for backup disk only
# export PROXMOX_BACKUP_STORAGE='backup-storage'
export PROXMOX_TEMPLATE_ID='9100'

export DNS_SERVER='10.10.92.53'
export SEARCH_DOMAIN='prod.home.arpa'

export CI_USER='aurus'
export CI_PASSWORD='Zz12345678'
export CLOUD_INIT_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"

# Optional
export BACKUP_DISK_SIZE_GB='200'
```

Notes:
- `PROXMOX_API_HOST` is enough; `PROXMOX_API_URL` is optional (used only as a fallback).
- No `!` is required in any variable (avoids bash history-expansion issues).

## Bootstrap (recommended)

```bash
./bootstrap.sh
source .venv/bin/activate
```

## Run
## Re-run without re-creating VMs

If VMs already exist in Proxmox, you can skip cloning step:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml -e provision_vms=false
```

