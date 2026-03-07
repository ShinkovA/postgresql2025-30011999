#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip install --upgrade pip wheel
python -m pip install -r requirements.txt

ansible-galaxy collection install -r requirements.yml

echo "OK: venv + dependencies installed."
echo "Next: export Proxmox/cloud-init env vars (see README.md) and run:" 
echo "  source .venv/bin/activate && ansible-playbook -i inventory/hosts.yml playbooks/site.yml"
