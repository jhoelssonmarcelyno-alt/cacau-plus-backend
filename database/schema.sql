-- ============================================================
-- CACAU PLUS — Schema do banco de dados PostgreSQL
-- Execute esse SQL no seu banco (Neon, Render, etc)
-- ============================================================

-- Extensão para UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Clientes ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS clientes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome              VARCHAR(150) NOT NULL,
  telefone          VARCHAR(20)  NOT NULL,
  email             VARCHAR(200) NOT NULL UNIQUE,
  senha_hash        TEXT         NOT NULL,
  ios_coins         NUMERIC(10,2) NOT NULL DEFAULT 0,
  codigo_indicacao  VARCHAR(20)  UNIQUE,
  indicado_por      VARCHAR(20),
  criado_em         TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ── Lojas ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS lojas (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome           VARCHAR(150) NOT NULL,
  cpf_cnpj       VARCHAR(20)  NOT NULL,
  endereco       TEXT         NOT NULL,
  telefone       VARCHAR(20)  NOT NULL,
  email          VARCHAR(200) NOT NULL UNIQUE,
  senha_hash     TEXT         NOT NULL,
  coins_por_real NUMERIC(6,2) NOT NULL DEFAULT 1.0,
  categoria      VARCHAR(100),
  criado_em      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ── Transações ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS transacoes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id  UUID NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  coins       NUMERIC(10,2) NOT NULL,
  tipo        VARCHAR(30) NOT NULL CHECK (tipo IN ('boas_vindas','indicacao','compra','resgate')),
  loja_id     UUID REFERENCES lojas(id),
  descricao   TEXT,
  criado_em   TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ── Prêmios ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS premios (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome        VARCHAR(150) NOT NULL,
  descricao   TEXT,
  custo_coins NUMERIC(10,2) NOT NULL,
  loja_id     UUID REFERENCES lojas(id),
  criado_em   TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ── Índices para performance ──────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_transacoes_cliente ON transacoes(cliente_id);
CREATE INDEX IF NOT EXISTS idx_clientes_codigo    ON clientes(codigo_indicacao);
CREATE INDEX IF NOT EXISTS idx_clientes_email     ON clientes(email);
CREATE INDEX IF NOT EXISTS idx_lojas_email        ON lojas(email);
