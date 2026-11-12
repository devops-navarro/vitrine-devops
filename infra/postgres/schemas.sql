-- Incluído pelo bootstrap.sql para cada banco (variável :alvo).

\connect :alvo
SET client_min_messages = warning;

-- Ninguém entra no banco por padrão, só quem recebe CONNECT
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'alvo') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO clientes, catalogo, pedidos', :'alvo') \gexec

-- Nada de tabela solta no schema public
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Cada serviço é dono do próprio schema e não recebe nada nos outros
CREATE SCHEMA IF NOT EXISTS clientes AUTHORIZATION clientes;
CREATE SCHEMA IF NOT EXISTS catalogo AUTHORIZATION catalogo;
CREATE SCHEMA IF NOT EXISTS pedidos AUTHORIZATION pedidos;
ALTER SCHEMA clientes OWNER TO clientes;
ALTER SCHEMA catalogo OWNER TO catalogo;
ALTER SCHEMA pedidos OWNER TO pedidos;
REVOKE ALL ON SCHEMA clientes, catalogo, pedidos FROM PUBLIC;

-- Tabelas criadas antes desta separação (pelo usuário administrador)
-- passam para o dono do schema. As sequences de identity vão junto.
SELECT format('ALTER TABLE %I.%I OWNER TO %I', schemaname, tablename, schemaname)
FROM pg_tables
WHERE schemaname IN ('clientes', 'catalogo', 'pedidos') AND tableowner <> schemaname \gexec
