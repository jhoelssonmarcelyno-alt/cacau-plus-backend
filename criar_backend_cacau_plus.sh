#!/bin/bash
# =============================================================
#  CACAU PLUS — Backend Node.js + PostgreSQL
#  Execute em uma pasta vazia chamada "backend":
#  mkdir backend && cd backend && bash criar_backend_cacau_plus.sh
# =============================================================

echo "🍫 Criando backend do Cacau Plus..."

# ─── PASTAS ──────────────────────────────────────────────────
mkdir -p src/controllers
mkdir -p src/routes
mkdir -p src/middlewares
mkdir -p src/models
mkdir -p src/config
mkdir -p src/utils

echo "✅ Pastas criadas!"

# ─── package.json ─────────────────────────────────────────────
cat > package.json << 'EOF'
{
  "name": "cacau-plus-backend",
  "version": "1.0.0",
  "description": "Backend do Cacau Plus — plataforma de fidelidade de Ilhéus",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "jsonwebtoken": "^9.0.2",
    "pg": "^8.12.0",
    "uuid": "^10.0.0"
  },
  "devDependencies": {
    "nodemon": "^3.1.4"
  }
}
EOF

# ─── .env.example ─────────────────────────────────────────────
cat > .env.example << 'EOF'
# Copie para .env e preencha com seus dados

# Banco de dados PostgreSQL (Neon, Render, etc)
DATABASE_URL=postgresql://usuario:senha@host/cacau_plus?sslmode=require

# Segredo do JWT — coloque uma string longa e aleatória
JWT_SECRET=coloque_um_segredo_muito_longo_aqui_123456

# Porta do servidor (Render usa PORT automático)
PORT=3000
EOF

# ─── .gitignore ───────────────────────────────────────────────
cat > .gitignore << 'EOF'
node_modules/
.env
EOF

# ─── src/config/db.js ─────────────────────────────────────────
cat > src/config/db.js << 'EOF'
// src/config/db.js
// Conexão com PostgreSQL via variável de ambiente DATABASE_URL

const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }, // Necessário para Neon/Render
});

pool.on('error', (err) => {
  console.error('Erro inesperado no pool do PostgreSQL:', err);
});

module.exports = pool;
EOF

# ─── src/config/jwt.js ────────────────────────────────────────
cat > src/config/jwt.js << 'EOF'
// src/config/jwt.js
// Geração e verificação de tokens JWT

const jwt = require('jsonwebtoken');
require('dotenv').config();

const SECRET = process.env.JWT_SECRET || 'cacau_plus_dev_secret';

function gerarToken(payload) {
  return jwt.sign(payload, SECRET, { expiresIn: '30d' });
}

function verificarToken(token) {
  return jwt.verify(token, SECRET);
}

module.exports = { gerarToken, verificarToken };
EOF

# ─── src/utils/resposta.js ────────────────────────────────────
cat > src/utils/resposta.js << 'EOF'
// src/utils/resposta.js
// Helpers para respostas padronizadas da API

function ok(res, dados, mensagem = 'Sucesso') {
  return res.status(200).json({ sucesso: true, mensagem, dados });
}

function criado(res, dados, mensagem = 'Criado com sucesso') {
  return res.status(201).json({ sucesso: true, mensagem, dados });
}

function erro(res, mensagem = 'Erro interno', status = 400) {
  return res.status(status).json({ sucesso: false, mensagem });
}

function naoAutorizado(res, mensagem = 'Não autorizado') {
  return res.status(401).json({ sucesso: false, mensagem });
}

module.exports = { ok, criado, erro, naoAutorizado };
EOF

# ─── src/middlewares/auth.js ──────────────────────────────────
cat > src/middlewares/auth.js << 'EOF'
// src/middlewares/auth.js
// Verifica JWT em rotas protegidas

const { verificarToken } = require('../config/jwt');
const { naoAutorizado } = require('../utils/resposta');

function autenticar(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return naoAutorizado(res);
  }
  const token = authHeader.split(' ')[1];
  try {
    req.usuario = verificarToken(token);
    next();
  } catch {
    return naoAutorizado(res, 'Token inválido ou expirado');
  }
}

function apenasCliente(req, res, next) {
  if (req.usuario?.tipo !== 'cliente') {
    return naoAutorizado(res, 'Acesso apenas para clientes');
  }
  next();
}

function apenasLoja(req, res, next) {
  if (req.usuario?.tipo !== 'loja') {
    return naoAutorizado(res, 'Acesso apenas para lojas');
  }
  next();
}

module.exports = { autenticar, apenasCliente, apenasLoja };
EOF

# ─── src/controllers/authController.js ───────────────────────
cat > src/controllers/authController.js << 'EOF'
// src/controllers/authController.js
// Cadastro e login de clientes e lojas

const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { gerarToken } = require('../config/jwt');
const { criado, ok, erro } = require('../utils/resposta');

const COINS_BOAS_VINDAS = 100;
const COINS_INDICACAO   = 50;

// ── Helpers ───────────────────────────────────────────────────
function gerarCodigoIndicacao(telefone) {
  const digits = telefone.replace(/\D/g, '');
  const suffix = digits.slice(-4).padStart(4, '0');
  return `CAC${suffix}${Date.now().toString().slice(-3)}`;
}

// ── POST /auth/cadastro-cliente ───────────────────────────────
async function cadastrarCliente(req, res) {
  const { nome, telefone, email, senha, codigoIndicacao } = req.body;

  if (!nome || !telefone || !email || !senha) {
    return erro(res, 'Campos obrigatórios: nome, telefone, email, senha');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Verifica e-mail duplicado
    const existe = await client.query(
      'SELECT id FROM clientes WHERE email = $1', [email.toLowerCase()]
    );
    if (existe.rows.length > 0) {
      await client.query('ROLLBACK');
      return erro(res, 'E-mail já cadastrado');
    }

    const hash   = await bcrypt.hash(senha, 10);
    const id     = uuidv4();
    const codigo = gerarCodigoIndicacao(telefone);

    await client.query(
      `INSERT INTO clientes (id, nome, telefone, email, senha_hash, ios_coins, codigo_indicacao, indicado_por)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [id, nome, telefone, email.toLowerCase(), hash, COINS_BOAS_VINDAS, codigo,
       codigoIndicacao || null]
    );

    // Registra transação de boas-vindas
    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'boas_vindas','Boas-vindas ao Cacau Plus!')`,
      [uuidv4(), id, COINS_BOAS_VINDAS]
    );

    // Credita coins de indicação para quem indicou
    if (codigoIndicacao) {
      const indicador = await client.query(
        'SELECT id FROM clientes WHERE codigo_indicacao = $1', [codigoIndicacao]
      );
      if (indicador.rows.length > 0) {
        const indId = indicador.rows[0].id;
        await client.query(
          'UPDATE clientes SET ios_coins = ios_coins + $1 WHERE id = $2',
          [COINS_INDICACAO, indId]
        );
        await client.query(
          `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
           VALUES ($1,$2,$3,'indicacao','Amigo indicado se cadastrou!')`,
          [uuidv4(), indId, COINS_INDICACAO]
        );
      }
    }

    await client.query('COMMIT');

    const token = gerarToken({ id, tipo: 'cliente', nome, email });
    return criado(res, { token, id, nome, email, iosCoins: COINS_BOAS_VINDAS, codigoIndicacao: codigo },
      'Cliente cadastrado com sucesso!');

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao cadastrar cliente', 500);
  } finally {
    client.release();
  }
}

// ── POST /auth/cadastro-loja ──────────────────────────────────
async function cadastrarLoja(req, res) {
  const { nome, cpfOuCnpj, endereco, telefone, email, senha, coinsPorReal, categoria } = req.body;

  if (!nome || !cpfOuCnpj || !endereco || !telefone || !email || !senha || !coinsPorReal) {
    return erro(res, 'Preencha todos os campos obrigatórios');
  }

  try {
    const existe = await pool.query(
      'SELECT id FROM lojas WHERE email = $1', [email.toLowerCase()]
    );
    if (existe.rows.length > 0) return erro(res, 'E-mail já cadastrado');

    const hash = await bcrypt.hash(senha, 10);
    const id   = uuidv4();

    await pool.query(
      `INSERT INTO lojas (id, nome, cpf_cnpj, endereco, telefone, email, senha_hash, coins_por_real, categoria)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [id, nome, cpfOuCnpj, endereco, telefone, email.toLowerCase(), hash,
       parseFloat(coinsPorReal), categoria || null]
    );

    const token = gerarToken({ id, tipo: 'loja', nome, email });
    return criado(res, { token, id, nome, email, coinsPorReal: parseFloat(coinsPorReal) },
      'Loja cadastrada com sucesso!');

  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao cadastrar loja', 500);
  }
}

// ── POST /auth/login ──────────────────────────────────────────
async function login(req, res) {
  const { email, senha } = req.body;
  if (!email || !senha) return erro(res, 'E-mail e senha obrigatórios');

  const emailNorm = email.toLowerCase();

  try {
    // Tenta cliente
    const resCliente = await pool.query(
      'SELECT * FROM clientes WHERE email = $1', [emailNorm]
    );
    if (resCliente.rows.length > 0) {
      const c = resCliente.rows[0];
      const ok_ = await bcrypt.compare(senha, c.senha_hash);
      if (!ok_) return erro(res, 'Senha incorreta', 401);

      const token = gerarToken({ id: c.id, tipo: 'cliente', nome: c.nome, email: c.email });
      return ok(res, {
        token, tipo: 'cliente',
        id: c.id, nome: c.nome, email: c.email,
        iosCoins: parseFloat(c.ios_coins),
        codigoIndicacao: c.codigo_indicacao,
      });
    }

    // Tenta loja
    const resLoja = await pool.query(
      'SELECT * FROM lojas WHERE email = $1', [emailNorm]
    );
    if (resLoja.rows.length > 0) {
      const l = resLoja.rows[0];
      const ok_ = await bcrypt.compare(senha, l.senha_hash);
      if (!ok_) return erro(res, 'Senha incorreta', 401);

      const token = gerarToken({ id: l.id, tipo: 'loja', nome: l.nome, email: l.email });
      return ok(res, {
        token, tipo: 'loja',
        id: l.id, nome: l.nome, email: l.email,
        coinsPorReal: parseFloat(l.coins_por_real),
        endereco: l.endereco,
      });
    }

    return erro(res, 'Nenhuma conta encontrada com esse e-mail', 404);

  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao fazer login', 500);
  }
}

module.exports = { cadastrarCliente, cadastrarLoja, login };
EOF

# ─── src/controllers/clienteController.js ────────────────────
cat > src/controllers/clienteController.js << 'EOF'
// src/controllers/clienteController.js
// Perfil e saldo do cliente

const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// GET /cliente/perfil
async function perfil(req, res) {
  try {
    const result = await pool.query(
      'SELECT id, nome, telefone, email, ios_coins, codigo_indicacao FROM clientes WHERE id = $1',
      [req.usuario.id]
    );
    if (result.rows.length === 0) return erro(res, 'Cliente não encontrado', 404);
    return ok(res, result.rows[0]);
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao buscar perfil', 500);
  }
}

// GET /cliente/extrato
async function extrato(req, res) {
  try {
    const result = await pool.query(
      `SELECT id, coins, tipo, descricao, loja_id, criado_em
       FROM transacoes WHERE cliente_id = $1
       ORDER BY criado_em DESC LIMIT 50`,
      [req.usuario.id]
    );
    return ok(res, result.rows);
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao buscar extrato', 500);
  }
}

module.exports = { perfil, extrato };
EOF

# ─── src/controllers/lojaController.js ───────────────────────
cat > src/controllers/lojaController.js << 'EOF'
// src/controllers/lojaController.js
// Perfil da loja e listagem pública

const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// GET /loja/perfil  (autenticado)
async function perfil(req, res) {
  try {
    const result = await pool.query(
      'SELECT id, nome, cpf_cnpj, endereco, telefone, email, coins_por_real, categoria FROM lojas WHERE id = $1',
      [req.usuario.id]
    );
    if (result.rows.length === 0) return erro(res, 'Loja não encontrada', 404);
    return ok(res, result.rows[0]);
  } catch (e) {
    return erro(res, 'Erro ao buscar perfil', 500);
  }
}

// PATCH /loja/coins-por-real  (autenticado)
async function atualizarCoinsPorReal(req, res) {
  const { coinsPorReal } = req.body;
  if (!coinsPorReal || isNaN(coinsPorReal) || coinsPorReal <= 0) {
    return erro(res, 'Valor inválido para coinsPorReal');
  }
  try {
    await pool.query(
      'UPDATE lojas SET coins_por_real = $1 WHERE id = $2',
      [parseFloat(coinsPorReal), req.usuario.id]
    );
    return ok(res, { coinsPorReal: parseFloat(coinsPorReal) }, 'Taxa atualizada!');
  } catch (e) {
    return erro(res, 'Erro ao atualizar taxa', 500);
  }
}

// GET /lojas  (público — listagem para o app cliente)
async function listarLojas(req, res) {
  try {
    const result = await pool.query(
      'SELECT id, nome, endereco, telefone, coins_por_real, categoria FROM lojas ORDER BY nome'
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao listar lojas', 500);
  }
}

module.exports = { perfil, atualizarCoinsPorReal, listarLojas };
EOF

# ─── src/controllers/coinsController.js ──────────────────────
cat > src/controllers/coinsController.js << 'EOF'
// src/controllers/coinsController.js
// Lógica de crédito de coins por compra (loja credita no cliente)

const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// POST /coins/creditar-compra
// Loja autenticada informa o cliente e o valor da compra
async function creditarCompra(req, res) {
  const { clienteId, valorCompra } = req.body;
  const lojaId = req.usuario.id;

  if (!clienteId || !valorCompra || isNaN(valorCompra) || valorCompra <= 0) {
    return erro(res, 'clienteId e valorCompra são obrigatórios');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Busca taxa da loja
    const resLoja = await client.query(
      'SELECT nome, coins_por_real FROM lojas WHERE id = $1', [lojaId]
    );
    if (resLoja.rows.length === 0) {
      await client.query('ROLLBACK');
      return erro(res, 'Loja não encontrada', 404);
    }

    const { nome: nomeL, coins_por_real } = resLoja.rows[0];
    const coinsGanhos = parseFloat(valorCompra) * parseFloat(coins_por_real);

    // Verifica cliente
    const resCliente = await client.query(
      'SELECT nome FROM clientes WHERE id = $1', [clienteId]
    );
    if (resCliente.rows.length === 0) {
      await client.query('ROLLBACK');
      return erro(res, 'Cliente não encontrado', 404);
    }

    // Credita coins
    await client.query(
      'UPDATE clientes SET ios_coins = ios_coins + $1 WHERE id = $2',
      [coinsGanhos, clienteId]
    );

    // Registra transação
    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, loja_id, descricao)
       VALUES ($1,$2,$3,'compra',$4,$5)`,
      [uuidv4(), clienteId, coinsGanhos, lojaId, `Compra em ${nomeL}`]
    );

    await client.query('COMMIT');

    return ok(res, {
      coinsGanhos: parseFloat(coinsGanhos.toFixed(2)),
      nomeCliente: resCliente.rows[0].nome,
    }, `${coinsGanhos.toFixed(0)} IOS Coins creditados!`);

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao creditar coins', 500);
  } finally {
    client.release();
  }
}

// POST /coins/resgatar
// Cliente resgata prêmio consumindo coins
async function resgatar(req, res) {
  const { premioId } = req.body;
  const clienteId = req.usuario.id;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const resPremio = await client.query(
      'SELECT * FROM premios WHERE id = $1', [premioId]
    );
    if (resPremio.rows.length === 0) {
      await client.query('ROLLBACK');
      return erro(res, 'Prêmio não encontrado', 404);
    }

    const premio = resPremio.rows[0];
    const resCliente = await client.query(
      'SELECT ios_coins FROM clientes WHERE id = $1', [clienteId]
    );
    const saldo = parseFloat(resCliente.rows[0].ios_coins);

    if (saldo < parseFloat(premio.custo_coins)) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Você tem ${saldo.toFixed(0)} coins, precisa de ${premio.custo_coins}`);
    }

    await client.query(
      'UPDATE clientes SET ios_coins = ios_coins - $1 WHERE id = $2',
      [premio.custo_coins, clienteId]
    );

    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'resgate',$4)`,
      [uuidv4(), clienteId, -parseFloat(premio.custo_coins), `Resgate: ${premio.nome}`]
    );

    await client.query('COMMIT');
    return ok(res, { novoSaldo: saldo - parseFloat(premio.custo_coins) }, `Prêmio "${premio.nome}" resgatado!`);

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao resgatar prêmio', 500);
  } finally {
    client.release();
  }
}

module.exports = { creditarCompra, resgatar };
EOF

# ─── src/controllers/premioController.js ─────────────────────
cat > src/controllers/premioController.js << 'EOF'
// src/controllers/premioController.js
// CRUD de prêmios disponíveis para resgate

const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, criado, erro } = require('../utils/resposta');

// GET /premios  (público)
async function listar(req, res) {
  try {
    const result = await pool.query('SELECT * FROM premios ORDER BY custo_coins');
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao listar prêmios', 500);
  }
}

// POST /premios  (loja autenticada cria prêmio)
async function criar(req, res) {
  const { nome, descricao, custoCoins } = req.body;
  if (!nome || !custoCoins) return erro(res, 'nome e custoCoins obrigatórios');

  try {
    const id = uuidv4();
    await pool.query(
      'INSERT INTO premios (id, nome, descricao, custo_coins, loja_id) VALUES ($1,$2,$3,$4,$5)',
      [id, nome, descricao || '', parseFloat(custoCoins), req.usuario.id]
    );
    return criado(res, { id, nome, custoCoins: parseFloat(custoCoins) });
  } catch (e) {
    return erro(res, 'Erro ao criar prêmio', 500);
  }
}

module.exports = { listar, criar };
EOF

# ─── src/routes/auth.js ───────────────────────────────────────
cat > src/routes/auth.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { cadastrarCliente, cadastrarLoja, login } = require('../controllers/authController');

router.post('/cadastro-cliente', cadastrarCliente);
router.post('/cadastro-loja',    cadastrarLoja);
router.post('/login',            login);

module.exports = router;
EOF

# ─── src/routes/cliente.js ────────────────────────────────────
cat > src/routes/cliente.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { perfil, extrato } = require('../controllers/clienteController');

router.use(autenticar, apenasCliente);
router.get('/perfil',  perfil);
router.get('/extrato', extrato);

module.exports = router;
EOF

# ─── src/routes/loja.js ───────────────────────────────────────
cat > src/routes/loja.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja } = require('../middlewares/auth');
const { perfil, atualizarCoinsPorReal, listarLojas } = require('../controllers/lojaController');

// Público
router.get('/', listarLojas);

// Autenticado (loja)
router.use(autenticar, apenasLoja);
router.get('/perfil',          perfil);
router.patch('/coins-por-real', atualizarCoinsPorReal);

module.exports = router;
EOF

# ─── src/routes/coins.js ──────────────────────────────────────
cat > src/routes/coins.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja, apenasCliente } = require('../middlewares/auth');
const { creditarCompra, resgatar } = require('../controllers/coinsController');

router.post('/creditar-compra', autenticar, apenasLoja,    creditarCompra);
router.post('/resgatar',        autenticar, apenasCliente, resgatar);

module.exports = router;
EOF

# ─── src/routes/premios.js ────────────────────────────────────
cat > src/routes/premios.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja } = require('../middlewares/auth');
const { listar, criar } = require('../controllers/premioController');

router.get('/',  listar);
router.post('/', autenticar, apenasLoja, criar);

module.exports = router;
EOF

# ─── src/server.js ────────────────────────────────────────────
cat > src/server.js << 'EOF'
// src/server.js
// Ponto de entrada do backend Cacau Plus

const express = require('express');
const cors    = require('cors');
require('dotenv').config();

const app = express();

app.use(cors());
app.use(express.json());

// Rotas
app.use('/auth',    require('./routes/auth'));
app.use('/cliente', require('./routes/cliente'));
app.use('/lojas',   require('./routes/loja'));
app.use('/coins',   require('./routes/coins'));
app.use('/premios', require('./routes/premios'));

// Health check (Render usa isso para saber se o server está de pé)
app.get('/health', (req, res) => res.json({ status: 'ok', app: 'Cacau Plus' }));

// 404
app.use((req, res) => res.status(404).json({ sucesso: false, mensagem: 'Rota não encontrada' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🍫 Cacau Plus backend rodando na porta ${PORT}`));
EOF

# ─── database/schema.sql ──────────────────────────────────────
mkdir -p database
cat > database/schema.sql << 'EOF'
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
EOF

# ─── render.yaml (deploy automático no Render) ────────────────
cat > render.yaml << 'EOF'
services:
  - type: web
    name: cacau-plus-backend
    runtime: node
    buildCommand: npm install
    startCommand: npm start
    envVars:
      - key: DATABASE_URL
        sync: false   # Você preenche no painel do Render
      - key: JWT_SECRET
        sync: false
EOF

echo ""
echo "✅ Backend do Cacau Plus criado com sucesso!"
echo ""
echo "📁 Estrutura:"
echo "   src/server.js"
echo "   src/config/db.js + jwt.js"
echo "   src/middlewares/auth.js"
echo "   src/controllers/ (auth, cliente, loja, coins, premio)"
echo "   src/routes/ (auth, cliente, loja, coins, premios)"
echo "   src/utils/resposta.js"
echo "   database/schema.sql"
echo "   render.yaml"
echo ""
echo "─────────────────────────────────────────────────────────"
echo "📋 PRÓXIMOS PASSOS:"
echo ""
echo "1. npm install"
echo ""
echo "2. Crie o banco no Neon (neon.tech) — é grátis"
echo "   Cole o DATABASE_URL no arquivo .env"
echo ""
echo "3. Execute o schema no banco:"
echo "   Abra o painel do Neon → SQL Editor → cole database/schema.sql"
echo ""
echo "4. Teste local:"
echo "   npm run dev"
echo ""
echo "5. Suba no Render:"
echo "   - New Web Service → conecte seu repositório GitHub"
echo "   - Adicione DATABASE_URL e JWT_SECRET nas variáveis de ambiente"
echo "   - Deploy automático!"
echo "─────────────────────────────────────────────────────────"
