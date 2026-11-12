# Fase 2 · Linux, redes e automação

Versão `v0.2.0`. Uma VM Ubuntu 26.04 LTS criada por código e configurada só pelo Ansible, monitorada com Prometheus, blackbox e Grafana, scripts Bash testados e redes explicadas com saídas reais.

## O que foi entregue

| Entrega | PR |
| --- | --- |
| VM do laboratório no Lima: Ubuntu 26.04 fixo, rede `vzNAT`, disco extra cru, `make lab-vm` / `lab-destroy` | #41 |
| Role `base`: usuário `deploy` só com chave, SSH sem root nem senha, `unattended-upgrades` | #42 |
| Role `web`: nginx com cabeçalhos de segurança, ufw negando por padrão, logrotate de 7 dias | #43 |
| Role `disco`: trava contra o disco errado, ext4, montagem por UUID com `nofail`; `known_hosts` pelo canal do Lima | #44 |
| Monitoração: node-exporter na VM; Prometheus, blackbox e Grafana com dashboard provisionado | #45 |
| Scripts Bash: backup, healthcheck e limpeza de logs, com 20 testes bats | #46 |
| CI: ansible-lint (perfil production), sintaxe do playbook, shellcheck e bats no Ubuntu | #47 |
| [Redes na prática](../redes.md): DNS, TCP, TLS, HTTP e diagnóstico com saídas reais | #48 |

## Critério de pronto

`make lab-destroy && make lab`, sem nenhuma VM, disco ou container antes:

| Medida | Resultado |
| --- | --- |
| Tempo total (VM + Ansible + monitoração) | 3 min 32 s |
| Primeira execução do playbook | `ok=34 changed=25 failed=0` |
| Segunda execução (`make lab-idempotencia`) | `ok=30 changed=0 unreachable=0 failed=0` |
| Passos manuais | nenhum |

Na VM recém-criada:

```
up                         node=1  web=1  prometheus=1
probe_success              web=1          (página com status 200 e "Hello World")
nginx no systemd           active=1
/usr/local/navarro         ext4, 1,9 GiB
ssh deploy (Strict=yes)    ok, Ubuntu 26.04.1 LTS
ufw                        Status: active
healthcheck.sh             ok: http://192.168.64.2/ respondeu 200
```

CI na `main`: sete jobs obrigatórios (`pre-commit`, `testes` dos 3 serviços, `compose`, `ansible`, `scripts`).

## Comportamentos provados

| Cenário | Resultado | PR |
| --- | --- | --- |
| `deploy` tentando senha; `root` com chave válida | `Permission denied (publickey)` nos dois | #42 |
| Servidor ouvindo na 8080, ufw ligado × desligado | Sem resposta × 200 | #43 |
| Reboot da VM | nginx `enabled/active`, ufw ativo, página 200 | #43 |
| logrotate forçado duas vezes | `access.log.1` e `access.log.2.gz` (`delaycompress`) | #43 |
| Arquivo no disco extra + reboot + playbook de novo | Arquivo intacto, sem reformatar | #44 |
| Role `disco` apontada para `/dev/vda` e `/dev/vdc` | Trava: "não parece ser o disco extra... Nada foi alterado" | #44 |
| nginx parado na VM | Teste sintético e estado do serviço a 0; voltam a 1 ao religar | #45 |
| Commit com erro de shellcheck e de ansible-lint | Os dois jobs do CI falham com a regra certa | #47 |
| Porta liberada sem serviço × porta bloqueada | curl erro 7 em ~1 s × erro 28 em 5 s | #48 |
| Sistema de arquivos com 64 inodes | `No space left on device` com 2% do espaço usado | #48 |

## Bugs e achados no caminho

Cada um está descrito no PR onde foi tratado.

- `apt update` contado como mudança depois de 1 hora, quebrando a idempotência (#42).
- Chave do host SSH trocando a cada partida da VM: o Lima gera um `instance-id` novo e o cloud-init regera as chaves. Resolvido lendo as chaves pelo canal local do Lima e apertando para `StrictHostKeyChecking=yes` (#44).
- Check de idempotência aprovando com a VM inalcançável, e `tee` escondendo o código de erro (#44).
- Rodízio de backup apagando o mais novo quando dois backups caíam no mesmo segundo (ordem ASCII de `-` e `.`) (#46).
- `lost+found` derrubando o backup feito por usuário comum (#46).
- Painel de inodes com `nan` para FAT (#45).

## Como reproduzir

```bash
uv tool install ansible-core ansible-lint
make lab                  # VM + Ansible + monitoração
make lab-idempotencia     # segunda execução sem mudanças
open http://localhost:3000
make scripts-test
make lab-destroy
```
