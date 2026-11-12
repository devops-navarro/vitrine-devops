-- Prepara o PostgreSQL para os serviços: um usuário por serviço, dono só do
-- próprio schema. Roda como administrador e pode rodar quantas vezes quiser.
--
-- As senhas vêm do ambiente (\getenv) para não aparecerem na linha de comando.
-- Uso: make db-bootstrap

\set ON_ERROR_STOP on
\getenv banco POSTGRES_DB
\getenv senha_clientes CLIENTES_DB_PASSWORD
\getenv senha_catalogo CATALOGO_DB_PASSWORD
\getenv senha_pedidos PEDIDOS_DB_PASSWORD

-- Usuários: cria se não existe e sempre redefine a senha, para o rodízio
-- ser só trocar o .env (ou o Secrets Manager) e rodar de novo.
CREATE TEMP TABLE servico (nome text, senha text);
INSERT INTO servico VALUES
    ('clientes', :'senha_clientes'),
    ('catalogo', :'senha_catalogo'),
    ('pedidos', :'senha_pedidos');

SELECT format('CREATE ROLE %I LOGIN', nome)
FROM servico WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = nome) \gexec

SELECT format('ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', nome, senha)
FROM servico \gexec

-- Banco de testes, ao lado do de desenvolvimento
SELECT format('CREATE DATABASE %I', :'banco' || '_test')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'banco' || '_test') \gexec

-- O mesmo preparo nos dois bancos
\set alvo :banco
\ir schemas.sql
SELECT :'banco' || '_test' AS alvo \gset
\ir schemas.sql
