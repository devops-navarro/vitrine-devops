# clientes

Cadastro de clientes e endereços. FastAPI + SQLAlchemy 2 + Alembic, em PostgreSQL no schema `clientes`.

## Rodando

Da raiz do repositório, com o `.env` criado a partir do `.env.example`:

```bash
make db-up              # PostgreSQL local
make db-bootstrap       # usuários e schemas dos serviços
make clientes-migrate   # cria/atualiza as tabelas
make clientes-run       # API em http://localhost:8001/docs
make clientes-test      # testes
```

## Autenticação

As rotas de negócio exigem o header `X-API-Key`. Sem ele, ou com chave errada, a resposta é 401. `/health` e a documentação (`/docs`) ficam abertos.

```bash
curl -H "X-API-Key: $CHAVE" localhost:8001/clientes
```

No `/docs`, o botão **Authorize** guarda a chave para todas as chamadas.

As chaves vêm de `API_KEYS`, separadas por vírgula, cada uma com 32+ caracteres (`openssl rand -hex 32`). Aceitar mais de uma permite trocar a chave sem parar ninguém: adiciona a nova, os consumidores migram, remove a antiga. O serviço não sobe sem chave ou com chave curta.

## Endpoints

| Método | Rota | Sucesso | Erros |
| --- | --- | --- | --- |
| `GET` | `/clientes?limit=20&offset=0` | 200 | 422 |
| `GET` | `/clientes/{id}` | 200 | 404 |
| `POST` | `/clientes` | 201 + `Location` | 409, 422 |
| `PUT` | `/clientes/{id}` | 200 | 404, 409, 422 |
| `DELETE` | `/clientes/{id}` | 204 | 404 |
| `GET` | `/clientes/{id}/enderecos` | 200 | 404 |
| `GET` | `/clientes/{id}/enderecos/{endereco_id}` | 200 | 404 |
| `POST` | `/clientes/{id}/enderecos` | 201 + `Location` | 404, 422 |
| `PUT` | `/clientes/{id}/enderecos/{endereco_id}` | 200 | 404, 422 |
| `DELETE` | `/clientes/{id}/enderecos/{endereco_id}` | 204 | 404 |

A listagem é paginada e limitada a 100 itens por chamada. O `PUT` substitui o recurso inteiro: campo opcional omitido volta a ser nulo.

Validação:
- CPF aceita máscara (`529.982.247-25`), é gravado só com dígitos e precisa ter dígitos verificadores válidos.
- E-mail é validado e gravado em minúsculas.
- CPF ou e-mail já cadastrado devolve 409. Quem garante a unicidade é o banco; a API traduz a constraint violada.

Endereços:
- Um cliente tem zero ou vários. Apagar o cliente apaga os endereços (`ON DELETE CASCADE`).
- No máximo um é o principal, garantido por índice único parcial (`WHERE principal`). O primeiro endereço vira principal; marcar outro como principal desmarca o anterior.
- CEP aceita máscara e é gravado com 8 dígitos. UF só aceita as 27 siglas.
- Um endereço só é acessível pela rota do próprio cliente: o id de outro cliente devolve 404.

## Estrutura

```
app/
  config.py   configuração por variável de ambiente (pydantic-settings)
  db.py       engine, sessão e schema do serviço
  deps.py     dependências compartilhadas pelas rotas
  seguranca.py  API key
  validacao.py  CPF e CEP
  models.py   tabelas
  schemas.py  formato de entrada e saída da API (Pydantic)
  routers/    rotas por recurso
  main.py     aplicação FastAPI
migrations/   migrations do Alembic, com a tabela de versão no próprio schema
tests/        pytest contra um PostgreSQL real
```

## Testes

Os testes rodam contra o PostgreSQL de verdade, num banco separado (`<POSTGRES_DB>_test`) que é criado e migrado sozinho. Cada teste roda dentro de uma transação desfeita no final, então a ordem não importa e nada vaza de um teste para outro.

## Migrations

A estrutura do banco muda só por migration, nunca à mão.

```bash
cd services/clientes
uv run alembic revision -m "descricao curta"   # nova migration
uv run alembic check                            # confere se o modelo e o banco batem
```
