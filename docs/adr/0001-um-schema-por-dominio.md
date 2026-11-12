# ADR 0001 · Um schema por domínio, um usuário por serviço

- **Status:** aceita

## Contexto

A Vitrine tem três serviços: `clientes`, `catalogo` e `pedidos`. O `pedidos` precisa saber se o cliente e os produtos existem. Três perguntas precisavam de resposta:

1. Os serviços usam o mesmo banco ou bancos separados?
2. O `pedidos` pode ler as tabelas dos outros direto, ou ter chave estrangeira para elas?
3. Os serviços são empacotados e implantados juntos ou separados?

O que pesa na decisão: custo na AWS (cada instância RDS é cobrada por hora), simplicidade para rodar localmente e liberdade para cada serviço evoluir sem quebrar os outros.

## Decisão

**Uma instância PostgreSQL, um schema por serviço, um usuário por serviço.**

- Cada serviço tem um usuário no banco com o mesmo nome do serviço, dono só do próprio schema. Ele não tem `USAGE` nos schemas dos outros, não cria banco, não cria schema e não escreve no `public`.
- Schemas, usuários e permissões são criados pela infraestrutura (`infra/postgres/`, `make db-bootstrap`), não pelo serviço. As migrations de cada serviço só criam tabelas dentro do schema que já existe.
- **Nenhuma consulta e nenhuma chave estrangeira atravessa schemas.** O `pedidos` confere cliente e produto pela API HTTP dos outros serviços e guarda uma cópia do que precisa (SKU, nome e preço no item do pedido).
- Cada serviço tem as próprias migrations, com a tabela `alembic_version` dentro do próprio schema.
- Cada serviço vira uma imagem própria e é implantado sozinho (Fase 4).

A regra não depende de disciplina: um teste em cada serviço (`tests/test_isolamento.py`) falha se ele conectar como administrador ou alcançar o schema de outro.

## Alternativas consideradas

- **Um schema só, tabelas compartilhadas.** Mais simples no início e permite `JOIN` entre domínios. Rejeitada: qualquer serviço poderia ler e alterar dados de outro, e mudar uma tabela exigiria coordenar todos os serviços que a usam.
- **Um banco (ou instância) por serviço.** O isolamento mais forte. Rejeitada por agora: três instâncias RDS triplicam o custo e a operação (backup, versão, monitoramento) num projeto com volume pequeno.
- **Mesmo schema separado por convenção, com um usuário só.** Rejeitada: a fronteira existiria só no código. Antes desta ADR era assim, e o usuário dos serviços era superusuário.
- **Chave estrangeira de `pedido.cliente_id` para `clientes.cliente`.** Daria integridade garantida pelo banco, mas prenderia o `pedidos` à estrutura interna do `clientes` e impediria separar os bancos depois.

## Consequências

- Separar um serviço numa instância própria no futuro é trocar `POSTGRES_HOST` e mover um schema, sem mudar código, porque nada atravessa schemas.
- O `pedidos` depende dos outros serviços estarem no ar para criar pedidos. Isso exige timeout, tratamento de falha e status corretos (feito na issue #8).
- A integridade entre domínios vira "existia no momento da criação", não "existe para sempre". Por isso produto usa soft delete e o item guarda o snapshot.
- Os serviços compartilham a instância: uma consulta pesada de um afeta os outros (vizinho barulhento), e o limite de conexões é de todos. Isso será acompanhado pelas métricas da Fase 6.
- Cada serviço tem uma senha própria. Na AWS elas vão para o Secrets Manager, uma por serviço, e o bootstrap roda com o usuário administrador da instância.
- Rodar localmente ganhou um passo: `make db-bootstrap` depois do `make db-up`.
