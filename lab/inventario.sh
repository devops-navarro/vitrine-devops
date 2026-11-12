#!/usr/bin/env bash
# Gera o inventário do Ansible a partir da VM do Lima: IP da rede vzNAT,
# usuário padrão da imagem e a chave que o Lima criou para ele.
set -euo pipefail

vm="${LAB_VM:-vitrine-lab}"
dir="$(cd "$(dirname "$0")" && pwd)"

ip="$(limactl shell "$vm" -- ip -4 -o addr show lima0 | awk '{split($4, a, "/"); print a[1]}')"
usuario="$(limactl shell "$vm" -- whoami)"

if [[ -z "$ip" ]]; then
  echo "não achei o IP da interface lima0 na VM $vm" >&2
  exit 1
fi

mkdir -p "$dir/.gerado"

# Chaves do host lidas pelo canal local do Lima, não pela rede da VM. Com elas,
# o SSH exige correspondência exata (StrictHostKeyChecking=yes). O Lima gera um
# instance-id novo a cada partida, e o cloud-init troca as chaves do host: por
# isso o known_hosts é refeito sempre que a VM é ligada.
limactl shell "$vm" -- sh -c 'cat /etc/ssh/ssh_host_*_key.pub' \
  | awk -v ip="$ip" '{print ip, $1, $2}' > "$dir/.gerado/known_hosts"
# Na rede vzNAT, o Mac é sempre o .1: é dele que vêm as coletas do Prometheus.
origem="${ip%.*}.1"

cat > "$dir/.gerado/inventario.ini" <<INI
[lab]
$vm ansible_host=$ip ansible_user=$usuario ansible_ssh_private_key_file=$HOME/.lima/_config/user ansible_python_interpreter=/usr/bin/python3 lab_monitor_origem=$origem
INI

# Alvos do Prometheus (file_sd): o IP da VM muda quando ela é recriada.
mkdir -p "$dir/.gerado/alvos"
cat > "$dir/.gerado/alvos/node.json" <<JSON
[{"targets": ["$ip:9100"], "labels": {"instancia": "$vm"}}]
JSON
cat > "$dir/.gerado/alvos/web.json" <<JSON
[{"targets": ["http://$ip/"], "labels": {"instancia": "$vm"}}]
JSON
echo "inventário: $vm em $ip"
