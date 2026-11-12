# Laboratório Linux

Uma VM Ubuntu 26.04 LTS no Mac, criada por código ([Lima](https://lima-vm.io/)) e configurada só pelo Ansible. É o servidor onde a Fase 2 pratica Linux, SSH, firewall, disco, monitoração e redes.

## Pré-requisitos

- macOS com [Lima](https://lima-vm.io/) (já vem com o Colima)
- `ansible-core` e `ansible-lint`: `uv tool install ansible-core ansible-lint`

## Uso

```bash
make lab           # tudo: coleções, VM e playbook
make lab-idempotencia  # roda de novo e falha se algo mudar
make lab-lint      # ansible-lint no perfil production

make lab-deps      # coleções do Ansible, versões fixas em requirements.yml
make lab-vm        # cria e liga a VM, gera o inventário e a chave do deploy
make lab-play      # roda o site.yml
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

## Roles

`site.yml` aplica as roles em ordem.

### base

| O que faz | Detalhe |
| --- | --- |
| Pacotes | Atualiza tudo (`apt dist-upgrade`) e garante `unattended-upgrades` ativo para correções de segurança |
| Usuário `deploy` | Sem senha, com a chave `.gerado/deploy_ed25519` (gerada no Mac, só a pública vai para a VM) e sudo validado por `visudo` antes de gravar |
| SSH | `sshd_config.d/01-vitrine.conf`: sem root, sem senha, só chave, 3 tentativas. Validado com `sshd -t` antes de gravar e aplicado com `reload`, que não derruba conexões abertas |

O arquivo do SSH começa com `01-` porque o sshd usa o primeiro valor que lê de cada opção, e os arquivos do `sshd_config.d` são lidos em ordem alfabética.

Acesso como `deploy`:

```bash
ssh -i lab/.gerado/deploy_ed25519 -o UserKnownHostsFile=lab/.gerado/known_hosts deploy@<ip da VM>
```

### web

| O que faz | Detalhe |
| --- | --- |
| nginx | Página própria em `/var/www/vitrine`, site padrão do pacote desativado, `server_tokens off` e cabeçalhos de segurança. Ligado agora e no boot (`enabled` + `started`) |
| Validação | Mudança de configuração avisa dois handlers em ordem: `nginx -t` e depois `reload`. Com erro, o reload não acontece e a versão antiga segue no ar |
| Firewall (ufw) | Libera 22 e 80, nega toda outra entrada e liga, nesta ordem, para o Ansible não perder o próprio SSH |
| Logs | logrotate diário, 7 cópias, compressão a partir da segunda (`delaycompress`) |

Página: `http://<ip da VM>/`.
