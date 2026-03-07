export PROXMOX_API_HOST='pve01.mgmt.home.arpa'
export PROXMOX_API_USER='ansible@pve'
export PROXMOX_API_TOKEN_ID='semaphore'
export PROXMOX_API_TOKEN_SECRET='__PUT_YOUR_TOKEN_SECRET_HERE__'

export PROXMOX_NODE='domushnik'
export PROXMOX_STORAGE='hdd-vmdata'
export PROXMOX_TEMPLATE_ID='9100'

export DNS_SERVER='10.10.92.53'
export SEARCH_DOMAIN='prod.home.arpa'

export CI_USER='aurus'
export CI_PASSWORD='__CHANGE_ME__'
export CLOUD_INIT_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"

export BACKUP_DISK_SIZE_GB='200'
