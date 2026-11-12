-- Schema do domínio de clientes.
-- Cada domínio tem o próprio schema no mesmo PostgreSQL (decisão detalhada na ADR 0001).

CREATE SCHEMA IF NOT EXISTS clientes;

CREATE TABLE IF NOT EXISTS clientes.cliente (
    -- identity é o padrão SQL atual; substitui o antigo SERIAL
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome           VARCHAR(150) NOT NULL,
    -- CPF guardado só com dígitos: CHAR porque o tamanho é sempre 11.
    -- Não é número: zeros à esquerda importam e ninguém faz conta com CPF.
    cpf            CHAR(11)     NOT NULL,
    -- 254 é o tamanho máximo de um e-mail válido (RFC 5321)
    email          VARCHAR(254) NOT NULL,
    -- texto e opcional: aceita DDI/DDD e nem todo cliente informa
    telefone       VARCHAR(20),
    -- TIMESTAMPTZ grava em UTC e evita confusão de fuso horário
    criado_em      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    atualizado_em  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT cliente_cpf_uk         UNIQUE (cpf),
    CONSTRAINT cliente_cpf_digitos_ck CHECK (cpf ~ '^[0-9]{11}$'),
    CONSTRAINT cliente_email_ck       CHECK (position('@' IN email) > 1)
);

-- E-mail único sem diferenciar maiúsculas: Ana@x.com e ana@x.com são o mesmo cliente
CREATE UNIQUE INDEX IF NOT EXISTS cliente_email_uk ON clientes.cliente (lower(email));
