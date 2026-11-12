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
cat > "$dir/.gerado/inventario.ini" <<INI
[lab]
$vm ansible_host=$ip ansible_user=$usuario ansible_ssh_private_key_file=$HOME/.lima/_config/user ansible_python_interpreter=/usr/bin/python3
INI
echo "inventário: $vm em $ip"
