# scripts

| Script | Para quê | Uso |
| --- | --- | --- |
| `backup.sh` | Compacta um diretório em `.tar.gz` com data no nome e mantém só os N mais recentes | `backup.sh <origem> <destino> [--manter N]` |
| `healthcheck.sh` | Testa uma URL: 2xx (e um texto esperado, se pedido), com novas tentativas | `healthcheck.sh <url> [--texto T] [--tentativas N] [--intervalo S] [--timeout S]` |
| `limpa-logs.sh` | Lista ou apaga logs mais velhos que N dias | `limpa-logs.sh <dir> [--dias N] [--aplicar]` |
| `smoke.py` | Confere o ambiente do compose no ar, de ponta a ponta | `make smoke` |
| `seed.py` | Popula dados de exemplo pelas APIs, de forma idempotente | `make seed` |

Os scripts Bash rodam no Bash 3.2 do macOS e no Bash 5 do Linux, começam com `set -euo pipefail` e seguem a mesma convenção de saída: `0` deu certo, `1` falhou, `2` uso incorreto.

Cuidados de cada um:
- **backup**: escreve num arquivo temporário e renomeia no fim, então nunca fica um backup pela metade com nome de completo. Nasce com permissão `600`. Ignora o `lost+found` do ext4. O sufixo `-NN` mantém a ordem alfabética igual à de idade mesmo com vários backups no mesmo segundo.
- **healthcheck**: distingue status errado, texto ausente e falta de resposta. Saída pronta para cron e CI.
- **limpa-logs**: sem `--aplicar`, só lista. Recusa a raiz e caminho vazio, só considera nomes de log (`*.log`, `*.log.N`, `*.log.N.gz`) e não segue link simbólico.

```bash
make scripts-lint    # shellcheck
make scripts-test    # testes com bats
```
