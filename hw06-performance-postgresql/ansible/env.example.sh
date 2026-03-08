export PROXMOX_API_HOST='pve01.example.local'
export PROXMOX_API_USER='ansible@pve'
export PROXMOX_API_TOKEN_ID='tokenid'
export PROXMOX_API_TOKEN_SECRET='tokensecret'

export PROXMOX_NODE='pve-node'
export PROXMOX_STORAGE='local-lvm'
export PROXMOX_TEMPLATE_ID='9100'

export DNS_SERVER='10.10.92.53'
export SEARCH_DOMAIN='prod.home.arpa'

export CI_USER='aurus'
export CI_PASSWORD='your-password'
export CLOUD_INIT_SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
