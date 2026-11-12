# Laboratório Linux

Uma VM Ubuntu 26.04 LTS no Mac, criada por código ([Lima](https://lima-vm.io/)) e configurada só pelo Ansible. É o servidor onde a Fase 2 pratica Linux, SSH, firewall, disco, monitoração e redes.

## Pré-requisitos

- macOS com [Lima](https://lima-vm.io/) (já vem com o Colima)
- `ansible-core` e `ansible-lint`: `uv tool install ansible-core ansible-lint`

## Uso

```bash
make lab-deps      # coleções do Ansible, versões fixas em requirements.yml
make lab-vm        # cria e liga a VM e gera o inventário
make lab-ping      # o Ansible alcança a VM?
make lab-ssh       # shell na VM
make lab-destroy   # apaga a VM, o disco extra e os arquivos gerados
```

## Como a VM é montada

| Item | Escolha | Por quê |
| --- | --- | --- |
| Sistema | Ubuntu 26.04 LTS, versão fixa | `ubuntu-lts` mudaria de versão sozinho |
| Recursos | 2 vCPU, 1,5 GB de RAM, 10 GB de disco | Cabe ao lado do Colima num Mac de 8 GB |
| Rede | `vzNAT`: IP próprio alcançável pelo Mac | Acesso como num servidor real, e o firewall filtra o tráfego de verdade |
| Portas | Nenhum repasse para o `localhost` do Mac | Tudo passa pelo IP da VM |
| Pastas | Nenhuma pasta do Mac montada | Servidor não enxerga arquivos pessoais |
| Disco extra | 2 GB cru, sem formatar | Partição e sistema de arquivos são trabalho do Ansible |

O inventário (`.gerado/inventario.ini`) é gerado por `inventario.sh` a partir da VM: IP da interface `lima0`, usuário padrão da imagem e a chave que o Lima criou. O SSH usa um `known_hosts` próprio do laboratório com `accept-new`, apagado junto com a VM: aceita a chave de uma VM nova e recusa se ela mudar depois.
