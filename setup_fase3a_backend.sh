#!/bin/bash
# Execute dentro de: /f/CACAU PLUS/Cacau_Plus/mobile/backend
# bash setup_fase3a_backend.sh

echo "🍫 Configurando backend Fase 3A..."

# ── niveisController.js ──────────────────────────────────────
cat > src/controllers/niveisController.js << 'EOF'
const pool = require('../config/db');

// Regras de nível
const NIVEIS = [
  { nome: 'bronze',   minCoins: 0,    cor: '#CD7F32', emoji: '🥉', beneficio: '1x coins padrão' },
  { nome: 'prata',    minCoins: 500,  cor: '#C0C0C0', emoji: '🥈', beneficio: '1.2x coins em compras' },
  { nome: 'ouro',     minCoins: 2000, cor: '#FFD700', emoji: '🥇', beneficio: '1.5x coins em compras' },
  { nome: 'diamante', minCoins: 5000, cor: '#B9F2FF', emoji: '💎', beneficio: '2x coins em compras' },
];

function calcularNivel(totalCoins) {
  for (let i = NIVEIS.length - 1; i >= 0; i--) {
    if (totalCoins >= NIVEIS[i].minCoins) return NIVEIS[i];
  }
  return NIVEIS[0];
}

function calcularMultiplicador(nivelNome) {
  switch (nivelNome) {
    case 'prata':    return 1.2;
    case 'ouro':     return 1.5;
    case 'diamante': return 2.0;
    default:         return 1.0;
  }
}

async function atualizarNivel(clienteId, client) {
  const res = await client.query(
    'SELECT nivel, total_coins_ganhos FROM clientes WHERE id=$1', [clienteId]
  );
  if (!res.rows.length) return;

  const totalCoins = parseFloat(res.rows[0].total_coins_ganhos);
  const nivelAtual = res.rows[0].nivel;
  const novoNivel  = calcularNivel(totalCoins).nome;

  if (novoNivel !== nivelAtual) {
    await client.query(
      'UPDATE clientes SET nivel=$1 WHERE id=$2', [novoNivel, clienteId]
    );

    // Notifica o cliente sobre mudança de nível
    const info = NIVEIS.find(n => n.nome === novoNivel);
    const { v4: uuidv4 } = require('uuid');
    await client.query(
      `INSERT INTO notificacoes (id, cliente_id, titulo, mensagem, tipo)
       VALUES ($1,$2,$3,$4,'nivel')`,
      [uuidv4(), clienteId,
       `${info.emoji} Você subiu para ${novoNivel.toUpperCase()}!`,
       `Parabéns! Agora você é ${novoNivel} e tem ${info.beneficio}!`]
    );

    return novoNivel;
  }
  return nivelAtual;
}

module.exports = { NIVEIS, calcularNivel, calcularMultiplicador, atualizarNivel };
EOF

# ── campanhasController.js ───────────────────────────────────
cat > src/controllers/campanhasController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, criado, erro } = require('../utils/resposta');

// GET /campanhas/ativa — verifica se há campanha ativa agora
async function campanhaAtiva(req, res) {
  try {
    const result = await pool.query(
      `SELECT * FROM campanhas
       WHERE ativo=true AND inicio <= NOW() AND fim >= NOW()
       ORDER BY multiplicador DESC LIMIT 1`
    );
    return ok(res, result.rows[0] || null);
  } catch (e) { return erro(res, 'Erro ao buscar campanha', 500); }
}

// GET /admin/campanhas — lista todas campanhas
async function listarCampanhas(req, res) {
  try {
    const result = await pool.query(
      'SELECT * FROM campanhas ORDER BY criado_em DESC'
    );
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao listar campanhas', 500); }
}

// POST /admin/campanhas — criar campanha
async function criarCampanha(req, res) {
  const { titulo, descricao, multiplicador, inicio, fim } = req.body;
  if (!titulo || !multiplicador || !inicio || !fim)
    return erro(res, 'titulo, multiplicador, inicio e fim são obrigatórios');
  if (multiplicador < 1.5 || multiplicador > 5)
    return erro(res, 'Multiplicador deve ser entre 1.5 e 5');

  try {
    const id = uuidv4();
    await pool.query(
      `INSERT INTO campanhas (id,titulo,descricao,multiplicador,inicio,fim)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [id, titulo, descricao || null, parseFloat(multiplicador),
       new Date(inicio), new Date(fim)]
    );

    // Notifica todos os clientes
    const clientes = await pool.query('SELECT id FROM clientes WHERE status=\'ativo\'');
    for (const c of clientes.rows) {
      await pool.query(
        `INSERT INTO notificacoes (id,cliente_id,titulo,mensagem,tipo)
         VALUES ($1,$2,$3,$4,'campanha')`,
        [uuidv4(), c.id,
         `🎉 ${titulo}`,
         descricao || `Campanha especial: ${multiplicador}x coins!`]
      );
    }

    return criado(res, { id, titulo, multiplicador }, 'Campanha criada e clientes notificados!');
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao criar campanha', 500);
  }
}

// PATCH /admin/campanhas/:id — editar/desativar campanha
async function editarCampanha(req, res) {
  const { id } = req.params;
  const { titulo, descricao, multiplicador, inicio, fim, ativo } = req.body;
  try {
    await pool.query(
      `UPDATE campanhas SET titulo=$1,descricao=$2,multiplicador=$3,
       inicio=$4,fim=$5,ativo=$6 WHERE id=$7`,
      [titulo, descricao, parseFloat(multiplicador),
       new Date(inicio), new Date(fim), ativo, id]
    );
    return ok(res, null, 'Campanha atualizada!');
  } catch (e) { return erro(res, 'Erro ao editar campanha', 500); }
}

module.exports = { campanhaAtiva, listarCampanhas, criarCampanha, editarCampanha };
EOF

# ── notificacoesController.js ────────────────────────────────
cat > src/controllers/notificacoesController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// GET /notificacoes — notificações do cliente logado
async function minhasNotificacoes(req, res) {
  const clienteId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT * FROM notificacoes
       WHERE (cliente_id=$1 OR cliente_id IS NULL)
       ORDER BY criado_em DESC LIMIT 30`,
      [clienteId]
    );
    const naoLidas = result.rows.filter(n => !n.lida).length;
    return ok(res, { notificacoes: result.rows, naoLidas });
  } catch (e) { return erro(res, 'Erro ao buscar notificações', 500); }
}

// PATCH /notificacoes/lerTodas — marca todas como lidas
async function lerTodas(req, res) {
  const clienteId = req.usuario.id;
  try {
    await pool.query(
      `UPDATE notificacoes SET lida=true
       WHERE (cliente_id=$1 OR cliente_id IS NULL) AND lida=false`,
      [clienteId]
    );
    return ok(res, null, 'Notificações lidas!');
  } catch (e) { return erro(res, 'Erro ao marcar notificações', 500); }
}

// POST /admin/notificacoes — admin envia notificação para todos ou um cliente
async function enviarNotificacao(req, res) {
  const { clienteId, titulo, mensagem, tipo } = req.body;
  if (!titulo || !mensagem) return erro(res, 'titulo e mensagem obrigatórios');

  try {
    if (clienteId) {
      // Para um cliente específico
      await pool.query(
        `INSERT INTO notificacoes (id,cliente_id,titulo,mensagem,tipo)
         VALUES ($1,$2,$3,$4,$5)`,
        [uuidv4(), clienteId, titulo, mensagem, tipo || 'geral']
      );
      return ok(res, null, 'Notificação enviada!');
    } else {
      // Para todos os clientes
      const clientes = await pool.query(
        'SELECT id FROM clientes WHERE status=\'ativo\''
      );
      for (const c of clientes.rows) {
        await pool.query(
          `INSERT INTO notificacoes (id,cliente_id,titulo,mensagem,tipo)
           VALUES ($1,$2,$3,$4,$5)`,
          [uuidv4(), c.id, titulo, mensagem, tipo || 'geral']
        );
      }
      return ok(res, { total: clientes.rows.length },
        `Notificação enviada para ${clientes.rows.length} clientes!`);
    }
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao enviar notificação', 500);
  }
}

module.exports = { minhasNotificacoes, lerTodas, enviarNotificacao };
EOF

# ── routes/campanhas.js ──────────────────────────────────────
cat > src/routes/campanhas.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar } = require('../middlewares/auth');
const { campanhaAtiva } = require('../controllers/campanhasController');

router.get('/ativa', autenticar, campanhaAtiva);
module.exports = router;
EOF

# ── routes/notificacoes.js ───────────────────────────────────
cat > src/routes/notificacoes.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { minhasNotificacoes, lerTodas } = require('../controllers/notificacoesController');

router.use(autenticar, apenasCliente);
router.get('/',          minhasNotificacoes);
router.patch('/lerTodas', lerTodas);
module.exports = router;
EOF

# ── routes/admin.js — adiciona campanhas e notificações ─────
cat > src/routes/admin.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasAdmin } = require('../middlewares/auth');
const {
  loginAdmin, dashboard,
  listarLojas, alterarStatusLoja,
  listarClientes, alterarStatusCliente,
  listarTarefas, criarTarefa, editarTarefa,
  listarPremios, criarPremio, deletarPremio,
  relatorio,
} = require('../controllers/adminController');
const { listarCampanhas, criarCampanha, editarCampanha } = require('../controllers/campanhasController');
const { enviarNotificacao } = require('../controllers/notificacoesController');

router.post('/login', loginAdmin);
router.use(autenticar, apenasAdmin);

router.get('/dashboard',              dashboard);
router.get('/lojas',                  listarLojas);
router.patch('/lojas/:id/status',     alterarStatusLoja);
router.get('/clientes',               listarClientes);
router.patch('/clientes/:id/status',  alterarStatusCliente);
router.get('/tarefas',                listarTarefas);
router.post('/tarefas',               criarTarefa);
router.patch('/tarefas/:id',          editarTarefa);
router.get('/premios',                listarPremios);
router.post('/premios',               criarPremio);
router.delete('/premios/:id',         deletarPremio);
router.get('/relatorio',              relatorio);
router.get('/campanhas',              listarCampanhas);
router.post('/campanhas',             criarCampanha);
router.patch('/campanhas/:id',        editarCampanha);
router.post('/notificacoes',          enviarNotificacao);

module.exports = router;
EOF

# ── coinsController.js — aplica multiplicador de nível e campanha
cat > src/controllers/coinsController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');
const { registrarVisita, verificarBrinde } = require('./fidelidadeController');
const { calcularMultiplicador, atualizarNivel } = require('./niveisController');

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
      'SELECT nome, ios_coins, nivel, total_coins_ganhos FROM clientes WHERE id=$1', [clienteId]
    );
    if (!resCliente.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Cliente não encontrado', 404); }
    const saldoAtual  = parseFloat(resCliente.rows[0].ios_coins);
    const nomeCliente = resCliente.rows[0].nome;
    const nivel       = resCliente.rows[0].nivel || 'bronze';

    if (coinsDesc > saldoAtual) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Cliente tem ${saldoAtual.toFixed(0)} coins.`);
    }

    const descontoPct   = coinsDesc / COINS_POR_PCT;
    const descontoReais = (valorCompra * descontoPct) / 100;
    const valorFinal    = valorCompra - descontoReais;
    const coinsPorReal  = parseFloat(loja.coins_por_real);

    // Verifica campanha ativa
    const resCampanha = await client.query(
      `SELECT multiplicador, titulo FROM campanhas
       WHERE ativo=true AND inicio <= NOW() AND fim >= NOW()
       ORDER BY multiplicador DESC LIMIT 1`
    );
    const campanha = resCampanha.rows[0];
    const multCampanha = campanha ? parseFloat(campanha.multiplicador) : 1;

    // Multiplicador de nível
    const multNivel = calcularMultiplicador(nivel);

    // Multiplicador final = maior entre nível e campanha
    const multiplicadorFinal = Math.max(multNivel, multCampanha);
    const coinsGanhos = valorFinal * coinsPorReal * multiplicadorFinal;
    const saldoFinal  = saldoAtual - coinsDesc + coinsGanhos;

    await client.query('UPDATE clientes SET ios_coins=$1, total_coins_ganhos = total_coins_ganhos + $2 WHERE id=$3',
      [saldoFinal, coinsGanhos, clienteId]);

    if (coinsDesc > 0) {
      await client.query(
        `INSERT INTO transacoes (id,cliente_id,coins,tipo,loja_id,descricao) VALUES ($1,$2,$3,'resgate',$4,$5)`,
        [uuidv4(), clienteId, -coinsDesc, lojaId, `Desconto ${descontoPct}% em ${loja.nome}`]
      );
    }
    await client.query(
      `INSERT INTO transacoes (id,cliente_id,coins,tipo,loja_id,descricao) VALUES ($1,$2,$3,'compra',$4,$5)`,
      [uuidv4(), clienteId, coinsGanhos, lojaId,
       `Compra em ${loja.nome} — R$ ${valorFinal.toFixed(2)}${multiplicadorFinal > 1 ? ` (${multiplicadorFinal}x)` : ''}`]
    );

    await registrarVisita(clienteId, lojaId, client);
    const brinde = await verificarBrinde(clienteId, lojaId, client);
    const novoNivel = await atualizarNivel(clienteId, client);

    await client.query('COMMIT');

    return ok(res, {
      nomeCliente,
      valorCompra:        parseFloat(valorCompra.toFixed(2)),
      descontoPct,
      descontoReais:      parseFloat(descontoReais.toFixed(2)),
      valorFinal:         parseFloat(valorFinal.toFixed(2)),
      coinsDebitados:     coinsDesc,
      coinsGanhos:        parseFloat(coinsGanhos.toFixed(2)),
      multiplicador:      multiplicadorFinal,
      campanhaAtiva:      campanha?.titulo || null,
      saldoAnterior:      parseFloat(saldoAtual.toFixed(2)),
      saldoFinal:         parseFloat(saldoFinal.toFixed(2)),
      nivel:              novoNivel,
      brinde,
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
      'SELECT nome, ios_coins, nivel FROM clientes WHERE id=$1', [clienteId]
    );
    if (!result.rows.length) return erro(res, 'Cliente não encontrado', 404);
    return ok(res, {
      nome:     result.rows[0].nome,
      iosCoins: parseFloat(result.rows[0].ios_coins),
      nivel:    result.rows[0].nivel,
    });
  } catch (e) { return erro(res, 'Erro ao buscar saldo', 500); }
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
const { setupAdmin } = require('./controllers/adminController');

const app = express();
app.use(cors());
app.use(express.json());

app.use('/auth',           require('./routes/auth'));
app.use('/cliente',        require('./routes/cliente'));
app.use('/lojas',          require('./routes/loja'));
app.use('/coins',          require('./routes/coins'));
app.use('/premios',        require('./routes/premios'));
app.use('/avaliacoes',     require('./routes/avaliacoes'));
app.use('/fidelidade',     require('./routes/fidelidade'));
app.use('/tarefas',        require('./routes/tarefas'));
app.use('/campanhas',      require('./routes/campanhas'));
app.use('/notificacoes',   require('./routes/notificacoes'));
app.use('/admin',          require('./routes/admin'));
app.use('/admin',          require('./routes/adminCoins'));

app.get('/health', (req, res) => res.json({ status: 'ok', app: 'Cacau Plus' }));
app.use((req, res) => res.status(404).json({ sucesso: false, mensagem: 'Rota não encontrada' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, async () => {
  console.log(`🍫 Cacau Plus backend rodando na porta ${PORT}`);
  await setupAdmin();
});
EOF

echo "✅ Backend Fase 3A configurado!"
git add .
git commit -m "feat: níveis, campanhas e notificações"
git push
echo "✅ Push feito!"