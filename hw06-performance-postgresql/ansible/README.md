# HW06 — PostgreSQL performance lab (Ansible)

Этот ansible-проект поднимает отдельную VM `pgperf-01`, ставит PostgreSQL 17,
готовит `pgbench`, применяет baseline / tuned profile и позволяет сравнить
результаты тестов.

## Структура

- `playbooks/create_perf_vm.yml` — создать VM в Proxmox
- `playbooks/configure_perf_vm.yml` — установить PostgreSQL + pgbench
- `playbooks/apply_baseline.yml` — вернуть почти дефолтный профиль
- `playbooks/apply_tuned.yml` — применить агрессивный benchmark profile
- `playbooks/prepare_pgbench.yml` — пересоздать БД `pgbench` и инициализировать dataset
- `playbooks/run_pgbench.yml` — запустить тест и сохранить результат в `results/`

## Быстрый старт

```bash
cd ansible
cp env.example.sh env.sh
vim env.sh
python3 -m venv .venv
source .venv/bin/activate
./bootstrap.sh
source ./env.sh

ansible-playbook -i inventory/hosts.yml playbooks/create_perf_vm.yml
ansible-playbook -i inventory/hosts.yml playbooks/configure_perf_vm.yml

# baseline
ansible-playbook -i inventory/hosts.yml playbooks/apply_baseline.yml
ansible-playbook -i inventory/hosts.yml playbooks/prepare_pgbench.yml
ansible-playbook -i inventory/hosts.yml playbooks/run_pgbench.yml -e pgbench_run_label=baseline

# tuned
ansible-playbook -i inventory/hosts.yml playbooks/apply_tuned.yml
ansible-playbook -i inventory/hosts.yml playbooks/prepare_pgbench.yml
ansible-playbook -i inventory/hosts.yml playbooks/run_pgbench.yml -e pgbench_run_label=tuned
```

## Важно

Tuned profile в этом ДЗ намеренно unsafe:
- `fsync=off`
- `full_page_writes=off`
- `synchronous_commit=off`
- `autovacuum=off`

Это допустимо только для benchmark / lab.
