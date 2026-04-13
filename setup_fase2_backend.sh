#!/bin/bash
# Execute dentro de: /f/CACAU PLUS/Cacau_Plus/mobile/backend
# bash setup_fase2_backend.sh

echo "🍫 Configurando backend Fase 2..."

# ── fidelidadeController.js ──────────────────────────────────
cat > src/controllers/fidelidadeController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, criado, erro } = require('../utils/resposta');

// Registra visita do cliente na loja (chamado automaticamente na compra)
async function registrarVisita(clienteId, lojaId, client) {
  await client.query(
    'INSERT INTO visitas (id, cliente_id, loja_id) VALUES ($1,$2,$3)',
    [uuidv4(), clienteId, lojaId]
  );
}

// Verifica se cliente ganhou brinde após visita
async function verificarBrinde(clienteId, lojaId, client) {
  const resLoja = await client.query(
    'SELECT fidelidade_ativo, fidelidade_visitas, fidelidade_brinde FROM lojas WHERE id=$1',
    [lojaId]
  );
  const loja = resLoja.rows[0];
  if (!loja.fidelidade_ativo || !loja.fidelidade_brinde) return null;

  const resVisitas = await client.query(
    'SELECT COUNT(*) FROM visitas WHERE cliente_id=$1 AND loja_id=$2',
    [clienteId, lojaId]
  );
  const total = parseInt(resVisitas.rows[0].count);
  const meta  = loja.fidelidade_visitas;

  if (total % meta === 0) {
    await client.query(
      'INSERT INTO brindes_resgatados (id, cliente_id, loja_id, brinde) VALUES ($1,$2,$3,$4)',
      [uuidv4(), clienteId, lojaId, loja.fidelidade_brinde]
    );
    return loja.fidelidade_brinde;
  }
  return null;
}

// GET /fidelidade/progresso/:lojaId — cliente vê progresso na loja
async function progressoCliente(req, res) {
  const clienteId = req.usuario.id;
  const { lojaId } = req.params;
  try {
    const resLoja = await pool.query(
      'SELECT nome, fidelidade_ativo, fidelidade_visitas, fidelidade_brinde FROM lojas WHERE id=$1',
      [lojaId]
    );
    if (!resLoja.rows.length) return erro(res, 'Loja não encontrada', 404);
    const loja = resLoja.rows[0];

    const resVisitas = await pool.query(
      'SELECT COUNT(*) FROM visitas WHERE cliente_id=$1 AND loja_id=$2',
      [clienteId, lojaId]
    );
    const totalVisitas = parseInt(resVisitas.rows[0].count);
    const meta = loja.fidelidade_visitas;
    const progresso = totalVisitas % meta;

    return ok(res, {
      lojaNome:         loja.nome,
      fidelidadeAtivo:  loja.fidelidade_ativo,
      meta,
      totalVisitas,
      progresso,
      faltam:           meta - progresso,
      brinde:           loja.fidelidade_brinde,
    });
  } catch (e) {
    return erro(res, 'Erro ao buscar progresso', 500);
  }
}

// GET /fidelidade/clientes — loja vê clientes fidelizados
async function clientesDaLoja(req, res) {
  const lojaId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT c.id, c.nome, c.telefone, c.email,
              COUNT(v.id) AS total_visitas,
              MAX(v.criado_em) AS ultima_visita,
              c.ios_coins
       FROM visitas v
       JOIN clientes c ON c.id = v.cliente_id
       WHERE v.loja_id = $1
       GROUP BY c.id, c.nome, c.telefone, c.email, c.ios_coins
       ORDER BY total_visitas DESC`,
      [lojaId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar clientes', 500);
  }
}

// GET /fidelidade/brindes — loja vê brindes concedidos
async function brindesDaLoja(req, res) {
  const lojaId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT b.id, b.brinde, b.criado_em, c.nome AS cliente_nome
       FROM brindes_resgatados b
       JOIN clientes c ON c.id = b.cliente_id
       WHERE b.loja_id = $1
       ORDER BY b.criado_em DESC LIMIT 50`,
      [lojaId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar brindes', 500);
  }
}

// PATCH /fidelidade/configurar — loja configura fidelidade
async function configurarFidelidade(req, res) {
  const lojaId = req.usuario.id;
  const { ativo, visitas, brinde } = req.body;
  if (ativo && (!visitas || visitas < 2)) {
    return erro(res, 'Informe quantas visitas para o brinde (mínimo 2)');
  }
  if (ativo && !brinde) {
    return erro(res, 'Informe o brinde');
  }
  try {
    await pool.query(
      'UPDATE lojas SET fidelidade_ativo=$1, fidelidade_visitas=$2, fidelidade_brinde=$3 WHERE id=$4',
      [ativo, visitas || 10, brinde || null, lojaId]
    );
    return ok(res, { ativo, visitas, brinde }, 'Fidelidade configurada!');
  } catch (e) {
    return erro(res, 'Erro ao configurar fidelidade', 500);
  }
}

// GET /fidelidade/transacoes — loja vê histórico de transações
async function transacoesDaLoja(req, res) {
  const lojaId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT t.id, t.coins, t.tipo, t.descricao, t.criado_em,
              c.nome AS cliente_nome
       FROM transacoes t
       JOIN clientes c ON c.id = t.cliente_id
       WHERE t.loja_id = $1
       ORDER BY t.criado_em DESC LIMIT 100`,
      [lojaId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar transações', 500);
  }
}

module.exports = {
  registrarVisita, verificarBrinde,
  progressoCliente, clientesDaLoja, brindesDaLoja,
  configurarFidelidade, transacoesDaLoja,
};
EOF

# ── tarefasController.js ─────────────────────────────────────
cat > src/controllers/tarefasController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// GET /tarefas — lista todas as tarefas com status do cliente
async function listarTarefas(req, res) {
  const clienteId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT t.id, t.titulo, t.descricao, t.coins, t.tipo, t.link,
              CASE WHEN tc.id IS NOT NULL THEN true ELSE false END AS concluida
       FROM tarefas t
       LEFT JOIN tarefas_concluidas tc
         ON tc.tarefa_id = t.id AND tc.cliente_id = $1
       WHERE t.ativo = true
       ORDER BY concluida ASC, t.coins DESC`,
      [clienteId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar tarefas', 500);
  }
}

// POST /tarefas/:id/concluir — cliente conclui uma tarefa
async function concluirTarefa(req, res) {
  const clienteId = req.usuario.id;
  const { id: tarefaId } = req.params;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Busca tarefa
    const resTarefa = await client.query(
      'SELECT * FROM tarefas WHERE id=$1 AND ativo=true', [tarefaId]
    );
    if (!resTarefa.rows.length) {
      await client.query('ROLLBACK');
      return erro(res, 'Tarefa não encontrada', 404);
    }
    const tarefa = resTarefa.rows[0];

    // Verifica se já concluiu
    const jaFez = await client.query(
      'SELECT id FROM tarefas_concluidas WHERE cliente_id=$1 AND tarefa_id=$2',
      [clienteId, tarefaId]
    );
    if (jaFez.rows.length) {
      await client.query('ROLLBACK');
      return erro(res, 'Você já completou esta tarefa!');
    }

    // Registra conclusão
    await client.query(
      'INSERT INTO tarefas_concluidas (id, cliente_id, tarefa_id) VALUES ($1,$2,$3)',
      [uuidv4(), clienteId, tarefaId]
    );

    // Credita coins
    await client.query(
      'UPDATE clientes SET ios_coins = ios_coins + $1 WHERE id = $2',
      [tarefa.coins, clienteId]
    );

    // Registra transação
    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'boas_vindas',$4)`,
      [uuidv4(), clienteId, tarefa.coins, `Tarefa concluída: ${tarefa.titulo}`]
    );

    await client.query('COMMIT');

    return ok(res, {
      coinsGanhos: parseFloat(tarefa.coins),
      tarefa: tarefa.titulo,
    }, `+${tarefa.coins} coins! Tarefa concluída!`);

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao concluir tarefa', 500);
  } finally {
    client.release();
  }
}

module.exports = { listarTarefas, concluirTarefa };
EOF

# ── routes/fidelidade.js ─────────────────────────────────────
cat > src/routes/fidelidade.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente, apenasLoja } = require('../middlewares/auth');
const {
  progressoCliente, clientesDaLoja, brindesDaLoja,
  configurarFidelidade, transacoesDaLoja,
} = require('../controllers/fidelidadeController');

router.get('/progresso/:lojaId', autenticar, apenasCliente, progressoCliente);
router.get('/clientes',          autenticar, apenasLoja,    clientesDaLoja);
router.get('/brindes',           autenticar, apenasLoja,    brindesDaLoja);
router.get('/transacoes',        autenticar, apenasLoja,    transacoesDaLoja);
router.patch('/configurar',      autenticar, apenasLoja,    configurarFidelidade);

module.exports = router;
EOF

# ── routes/tarefas.js ────────────────────────────────────────
cat > src/routes/tarefas.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { listarTarefas, concluirTarefa } = require('../controllers/tarefasController');

router.get('/',              autenticar, apenasCliente, listarTarefas);
router.post('/:id/concluir', autenticar, apenasCliente, concluirTarefa);

module.exports = router;
EOF

# ── coinsController.js — adiciona visita + brinde na compra ──
cat > src/controllers/coinsController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');
const { registrarVisita, verificarBrinde } = require('./fidelidadeController');

const COINS_POR_PCT = 100;
const MINIMO_COINS  = 500;

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
      'SELECT nome, coins_por_real, desconto_max_pct FROM lojas WHERE id=$1', [lojaId]
    );
    if (!resLoja.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Loja não encontrada', 404); }
    const loja = resLoja.rows[0];
    const maxCoinsDesc = parseFloat(loja.desconto_max_pct) * COINS_POR_PCT;

    if (coinsDesc > maxCoinsDesc) {
      await client.query('ROLLBACK');
      return erro(res, `Loja aceita no máximo ${maxCoinsDesc} coins de desconto`);
    }

    const resCliente = await client.query(
      'SELECT nome, ios_coins FROM clientes WHERE id=$1', [clienteId]
    );
    if (!resCliente.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Cliente não encontrado', 404); }
    const saldoAtual  = parseFloat(resCliente.rows[0].ios_coins);
    const nomeCliente = resCliente.rows[0].nome;

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

    await client.query('UPDATE clientes SET ios_coins=$1 WHERE id=$2', [saldoFinal, clienteId]);

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

    // Registra visita e verifica brinde
    await registrarVisita(clienteId, lojaId, client);
    const brinde = await verificarBrinde(clienteId, lojaId, client);

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
      brinde,         // null ou nome do brinde ganho
    }, 'Compra processada!');

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao processar compra', 500);
  } finally {
    client.release();
  }
}

async function buscarSaldoCliente(req, res) {
  const { clienteId } = req.params;
  try {
    const result = await pool.query(
      'SELECT nome, ios_coins FROM clientes WHERE id=$1', [clienteId]
    );
    if (!result.rows.length) return erro(res, 'Cliente não encontrado', 404);
    return ok(res, {
      nome:     result.rows[0].nome,
      iosCoins: parseFloat(result.rows[0].ios_coins),
    });
  } catch (e) {
    return erro(res, 'Erro ao buscar saldo', 500);
  }
}

async function resgatar(req, res) {
  const { premioId } = req.body;
  const clienteId = req.usuario.id;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const resPremio = await client.query('SELECT * FROM premios WHERE id=$1', [premioId]);
    if (!resPremio.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Prêmio não encontrado', 404); }
    const premio = resPremio.rows[0];
    const resC = await client.query('SELECT ios_coins FROM clientes WHERE id=$1', [clienteId]);
    const saldo = parseFloat(resC.rows[0].ios_coins);
    if (saldo < parseFloat(premio.custo_coins)) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Você tem ${saldo.toFixed(0)} coins.`);
    }
    await client.query('UPDATE clientes SET ios_coins = ios_coins - $1 WHERE id=$2', [premio.custo_coins, clienteId]);
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

# ── server.js ─────────────────────────────────────────────────
cat > src/server.js << 'EOF'
const express = require('express');
const cors    = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

app.use('/auth',        require('./routes/auth'));
app.use('/cliente',     require('./routes/cliente'));
app.use('/lojas',       require('./routes/loja'));
app.use('/coins',       require('./routes/coins'));
app.use('/premios',     require('./routes/premios'));
app.use('/avaliacoes',  require('./routes/avaliacoes'));
app.use('/fidelidade',  require('./routes/fidelidade'));
app.use('/tarefas',     require('./routes/tarefas'));

app.get('/health', (req, res) => res.json({ status: 'ok', app: 'Cacau Plus' }));
app.use((req, res) => res.status(404).json({ sucesso: false, mensagem: 'Rota não encontrada' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🍫 Cacau Plus backend rodando na porta ${PORT}`));
EOF

echo "✅ Backend Fase 2 configurado!"
git add .
git commit -m "feat: fidelidade, tarefas e histórico de clientes"
git push
echo "✅ Push feito! Aguarde o Render fazer deploy."
