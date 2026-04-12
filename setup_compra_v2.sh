#!/bin/bash
# Execute dentro de: /f/CACAU PLUS/Cacau_Plus/mobile/backend
# bash setup_compra_v2.sh

echo "🍫 Configurando sistema de compra com desconto..."

# ── coinsController.js ───────────────────────────────────────
cat > src/controllers/coinsController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

const COINS_POR_PCT = 100;
const MINIMO_COINS  = 500;

// POST /coins/compra
async function processarCompra(req, res) {
  const lojaId = req.usuario.id;
  const { clienteId, valorCompra, coinsParaDescontar } = req.body;
  if (!clienteId || !valorCompra || valorCompra <= 0)
    return erro(res, 'clienteId e valorCompra são obrigatórios');

  const coinsDesc = coinsParaDescontar || 0;
  if (coinsDesc > 0 && coinsDesc < MINIMO_COINS)
    return erro(res, `Mínimo de ${MINIMO_COINS} coins para desconto`);
  if (coinsDesc % COINS_POR_PCT !== 0)
    return erro(res, 'Coins deve ser múltiplo de 100');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const resLoja = await client.query(
      'SELECT nome, coins_por_real, desconto_max_pct FROM lojas WHERE id = $1', [lojaId]
    );
    if (!resLoja.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Loja não encontrada', 404); }
    const loja = resLoja.rows[0];
    const maxCoinsDesc = parseFloat(loja.desconto_max_pct) * COINS_POR_PCT;

    if (coinsDesc > maxCoinsDesc) {
      await client.query('ROLLBACK');
      return erro(res, `Loja aceita no máximo ${maxCoinsDesc} coins de desconto (${loja.desconto_max_pct}%)`);
    }

    const resCliente = await client.query(
      'SELECT nome, ios_coins FROM clientes WHERE id = $1', [clienteId]
    );
    if (!resCliente.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Cliente não encontrado', 404); }
    const saldoAtual   = parseFloat(resCliente.rows[0].ios_coins);
    const nomeCliente  = resCliente.rows[0].nome;

    if (coinsDesc > saldoAtual) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Cliente tem ${saldoAtual.toFixed(0)} coins.`);
    }

    const descontoPct   = coinsDesc / COINS_POR_PCT;
    const descontoReais = (valorCompra * descontoPct) / 100;
    const valorFinal    = valorCompra - descontoReais;
    const coinsPorReal  = parseFloat(loja.coins_por_real);
    const coinsGanhos   = valorFinal * coinsPorReal;
    const saldoFinal    = saldoAtual - coinsDesc + coinsGanhos;

    await client.query('UPDATE clientes SET ios_coins = $1 WHERE id = $2', [saldoFinal, clienteId]);

    if (coinsDesc > 0) {
      await client.query(
        `INSERT INTO transacoes (id,cliente_id,coins,tipo,loja_id,descricao) VALUES ($1,$2,$3,'resgate',$4,$5)`,
        [uuidv4(), clienteId, -coinsDesc, lojaId, `Desconto ${descontoPct}% em ${loja.nome}`]
      );
    }
    await client.query(
      `INSERT INTO transacoes (id,cliente_id,coins,tipo,loja_id,descricao) VALUES ($1,$2,$3,'compra',$4,$5)`,
      [uuidv4(), clienteId, coinsGanhos, lojaId, `Compra em ${loja.nome} — R$ ${valorFinal.toFixed(2)}`]
    );

    await client.query('COMMIT');
    return ok(res, {
      nomeCliente,
      valorCompra:    parseFloat(valorCompra.toFixed(2)),
      descontoPct,
      descontoReais:  parseFloat(descontoReais.toFixed(2)),
      valorFinal:     parseFloat(valorFinal.toFixed(2)),
      coinsDebitados: coinsDesc,
      coinsGanhos:    parseFloat(coinsGanhos.toFixed(2)),
      saldoAnterior:  parseFloat(saldoAtual.toFixed(2)),
      saldoFinal:     parseFloat(saldoFinal.toFixed(2)),
    }, 'Compra processada!');

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao processar compra', 500);
  } finally {
    client.release();
  }
}

// GET /coins/saldo/:clienteId
async function buscarSaldoCliente(req, res) {
  const { clienteId } = req.params;
  try {
    const result = await pool.query(
      'SELECT nome, ios_coins FROM clientes WHERE id = $1', [clienteId]
    );
    if (!result.rows.length) return erro(res, 'Cliente não encontrado', 404);
    return ok(res, { nome: result.rows[0].nome, iosCoins: parseFloat(result.rows[0].ios_coins) });
  } catch (e) {
    return erro(res, 'Erro ao buscar saldo', 500);
  }
}

// POST /coins/resgatar
async function resgatar(req, res) {
  const { premioId } = req.body;
  const clienteId = req.usuario.id;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const resPremio = await client.query('SELECT * FROM premios WHERE id = $1', [premioId]);
    if (!resPremio.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Prêmio não encontrado', 404); }
    const premio = resPremio.rows[0];
    const resC = await client.query('SELECT ios_coins FROM clientes WHERE id = $1', [clienteId]);
    const saldo = parseFloat(resC.rows[0].ios_coins);
    if (saldo < parseFloat(premio.custo_coins)) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Você tem ${saldo.toFixed(0)} coins.`);
    }
    await client.query('UPDATE clientes SET ios_coins = ios_coins - $1 WHERE id = $2', [premio.custo_coins, clienteId]);
    await client.query(
      `INSERT INTO transacoes (id,cliente_id,coins,tipo,descricao) VALUES ($1,$2,$3,'resgate',$4)`,
      [uuidv4(), clienteId, -parseFloat(premio.custo_coins), `Resgate: ${premio.nome}`]
    );
    await client.query('COMMIT');
    return ok(res, { novoSaldo: saldo - parseFloat(premio.custo_coins) }, `Prêmio resgatado!`);
  } catch (e) {
    await client.query('ROLLBACK');
    return erro(res, 'Erro ao resgatar', 500);
  } finally {
    client.release();
  }
}

module.exports = { processarCompra, buscarSaldoCliente, resgatar };
EOF

# ── routes/coins.js ──────────────────────────────────────────
cat > src/routes/coins.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja, apenasCliente } = require('../middlewares/auth');
const { processarCompra, buscarSaldoCliente, resgatar } = require('../controllers/coinsController');

router.post('/compra',          autenticar, apenasLoja,    processarCompra);
router.get('/saldo/:clienteId', autenticar, apenasLoja,    buscarSaldoCliente);
router.post('/resgatar',        autenticar, apenasCliente, resgatar);

module.exports = router;
EOF

# ── routes/loja.js — adiciona rota configurar ────────────────
cat > src/routes/loja.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja } = require('../middlewares/auth');
const { perfil, atualizarCoinsPorReal, listarLojas, configurarLoja } = require('../controllers/lojaController');

router.get('/', listarLojas);
router.use(autenticar, apenasLoja);
router.get('/perfil',          perfil);
router.patch('/coins-por-real', atualizarCoinsPorReal);
router.patch('/configurar',    configurarLoja);

module.exports = router;
EOF

# ── lojaController.js — adiciona configurarLoja ──────────────
cat > src/controllers/lojaController.js << 'EOF'
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

async function perfil(req, res) {
  try {
    const r = await pool.query(
      'SELECT id,nome,cpf_cnpj,endereco,telefone,email,coins_por_real,desconto_max_pct,categoria FROM lojas WHERE id=$1',
      [req.usuario.id]
    );
    if (!r.rows.length) return erro(res, 'Loja não encontrada', 404);
    return ok(res, r.rows[0]);
  } catch (e) { return erro(res, 'Erro ao buscar perfil', 500); }
}

async function atualizarCoinsPorReal(req, res) {
  const { coinsPorReal } = req.body;
  if (!coinsPorReal || isNaN(coinsPorReal) || coinsPorReal <= 0)
    return erro(res, 'Valor inválido');
  try {
    await pool.query('UPDATE lojas SET coins_por_real=$1 WHERE id=$2',
      [parseFloat(coinsPorReal), req.usuario.id]);
    return ok(res, { coinsPorReal: parseFloat(coinsPorReal) }, 'Taxa atualizada!');
  } catch (e) { return erro(res, 'Erro ao atualizar', 500); }
}

async function configurarLoja(req, res) {
  const { coinsPorReal, descontoMaxPct } = req.body;
  if (!coinsPorReal || !descontoMaxPct)
    return erro(res, 'coinsPorReal e descontoMaxPct são obrigatórios');
  if (descontoMaxPct < 5 || descontoMaxPct > 30)
    return erro(res, 'Desconto máximo deve ser entre 5% e 30%');
  try {
    await pool.query(
      'UPDATE lojas SET coins_por_real=$1, desconto_max_pct=$2 WHERE id=$3',
      [parseFloat(coinsPorReal), parseFloat(descontoMaxPct), req.usuario.id]
    );
    return ok(res, { coinsPorReal: parseFloat(coinsPorReal), descontoMaxPct: parseFloat(descontoMaxPct) }, 'Configurações salvas!');
  } catch (e) { return erro(res, 'Erro ao salvar', 500); }
}

async function listarLojas(req, res) {
  try {
    const r = await pool.query(
      'SELECT id,nome,endereco,telefone,coins_por_real,desconto_max_pct,categoria FROM lojas ORDER BY nome'
    );
    return ok(res, r.rows);
  } catch (e) { return erro(res, 'Erro ao listar lojas', 500); }
}

module.exports = { perfil, atualizarCoinsPorReal, configurarLoja, listarLojas };
EOF

# ── server.js ─────────────────────────────────────────────────
cat > src/server.js << 'EOF'
const express = require('express');
const cors    = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

app.use('/auth',       require('./routes/auth'));
app.use('/cliente',    require('./routes/cliente'));
app.use('/lojas',      require('./routes/loja'));
app.use('/coins',      require('./routes/coins'));
app.use('/premios',    require('./routes/premios'));
app.use('/avaliacoes', require('./routes/avaliacoes'));

app.get('/health', (req, res) => res.json({ status: 'ok', app: 'Cacau Plus' }));
app.use((req, res) => res.status(404).json({ sucesso: false, mensagem: 'Rota não encontrada' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🍫 Cacau Plus backend rodando na porta ${PORT}`));
EOF

echo "✅ Backend configurado!"
git add .
git commit -m "feat: sistema de compra com desconto por coins"
git push
echo "✅ Push feito! Aguarde o Render fazer deploy."
