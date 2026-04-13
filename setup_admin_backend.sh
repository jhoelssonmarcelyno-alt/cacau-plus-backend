#!/bin/bash
# Execute dentro de: /f/CACAU PLUS/Cacau_Plus/mobile/backend
# bash setup_admin_backend.sh

echo "🍫 Configurando backend Admin..."

# ── middlewares/auth.js — adiciona autenticarAdmin ───────────
cat > src/middlewares/auth.js << 'EOF'
const { verificarToken } = require('../config/jwt');
const { naoAutorizado } = require('../utils/resposta');

function autenticar(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) return naoAutorizado(res);
  const token = authHeader.split(' ')[1];
  try {
    req.usuario = verificarToken(token);
    next();
  } catch {
    return naoAutorizado(res, 'Token inválido ou expirado');
  }
}

function apenasCliente(req, res, next) {
  if (req.usuario?.tipo !== 'cliente') return naoAutorizado(res, 'Acesso apenas para clientes');
  next();
}

function apenasLoja(req, res, next) {
  if (req.usuario?.tipo !== 'loja') return naoAutorizado(res, 'Acesso apenas para lojas');
  next();
}

function apenasAdmin(req, res, next) {
  if (req.usuario?.tipo !== 'admin') return naoAutorizado(res, 'Acesso apenas para administradores');
  next();
}

module.exports = { autenticar, apenasCliente, apenasLoja, apenasAdmin };
EOF

# ── adminController.js ───────────────────────────────────────
cat > src/controllers/adminController.js << 'EOF'
const bcrypt  = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const pool    = require('../config/db');
const { gerarToken } = require('../config/jwt');
const { ok, criado, erro } = require('../utils/resposta');

// ── Setup: cria admin padrão se não existir ──────────────────
async function setupAdmin() {
  try {
    const existe = await pool.query('SELECT id FROM admins WHERE email=$1',
      ['jhoelssonmarcelyno@gmail.com']);
    if (existe.rows.length === 0) {
      const hash = await bcrypt.hash('4@Mandamento', 10);
      await pool.query(
        'INSERT INTO admins (id,nome,email,senha_hash) VALUES ($1,$2,$3,$4)',
        [uuidv4(), 'Jhoelsson', 'jhoelssonmarcelyno@gmail.com', hash]
      );
      console.log('✅ Admin padrão criado!');
    }
  } catch (e) {
    console.error('Erro ao criar admin padrão:', e.message);
  }
}

// POST /admin/login
async function loginAdmin(req, res) {
  const { email, senha } = req.body;
  if (!email || !senha) return erro(res, 'E-mail e senha obrigatórios');
  try {
    const result = await pool.query(
      'SELECT * FROM admins WHERE email=$1 AND ativo=true',
      [email.toLowerCase()]
    );
    if (!result.rows.length) return erro(res, 'Admin não encontrado', 404);
    const admin = result.rows[0];
    const ok_ = await bcrypt.compare(senha, admin.senha_hash);
    if (!ok_) return erro(res, 'Senha incorreta', 401);
    const token = gerarToken({ id: admin.id, tipo: 'admin', nome: admin.nome, email: admin.email });
    return ok(res, { token, id: admin.id, nome: admin.nome, email: admin.email });
  } catch (e) {
    return erro(res, 'Erro ao fazer login', 500);
  }
}

// GET /admin/dashboard — métricas gerais
async function dashboard(req, res) {
  try {
    const [clientes, lojas, coins, transacoesHoje, tarefas] = await Promise.all([
      pool.query('SELECT COUNT(*) FROM clientes'),
      pool.query('SELECT COUNT(*) FROM lojas'),
      pool.query('SELECT COALESCE(SUM(ios_coins),0) AS total FROM clientes'),
      pool.query(`SELECT COUNT(*) FROM transacoes WHERE criado_em >= NOW() - INTERVAL '24 hours'`),
      pool.query('SELECT COUNT(*) FROM tarefas WHERE ativo=true'),
    ]);

    // Coins movimentados hoje
    const coinsHoje = await pool.query(
      `SELECT COALESCE(SUM(ABS(coins)),0) AS total FROM transacoes
       WHERE criado_em >= NOW() - INTERVAL '24 hours'`
    );

    // Novos cadastros últimos 7 dias
    const novos7d = await pool.query(
      `SELECT COUNT(*) FROM clientes WHERE criado_em >= NOW() - INTERVAL '7 days'`
    );

    return ok(res, {
      totalClientes:    parseInt(clientes.rows[0].count),
      totalLojas:       parseInt(lojas.rows[0].count),
      totalCoinsAtivos: parseFloat(coins.rows[0].total),
      transacoesHoje:   parseInt(transacoesHoje.rows[0].count),
      coinsMovHoje:     parseFloat(coinsHoje.rows[0].total),
      tarefasAtivas:    parseInt(tarefas.rows[0].count),
      novosClientes7d:  parseInt(novos7d.rows[0].count),
    });
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao buscar dashboard', 500);
  }
}

// GET /admin/lojas — lista lojas com status
async function listarLojas(req, res) {
  try {
    const result = await pool.query(
      `SELECT id,nome,email,telefone,endereco,status,coins_por_real,
              desconto_max_pct,criado_em,
              (SELECT COUNT(*) FROM transacoes WHERE loja_id=lojas.id) AS total_transacoes
       FROM lojas ORDER BY criado_em DESC`
    );
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao listar lojas', 500); }
}

// PATCH /admin/lojas/:id/status
async function alterarStatusLoja(req, res) {
  const { id } = req.params;
  const { status } = req.body;
  if (!['ativo','bloqueado','pendente'].includes(status))
    return erro(res, 'Status inválido. Use: ativo, bloqueado ou pendente');
  try {
    await pool.query('UPDATE lojas SET status=$1 WHERE id=$2', [status, id]);
    return ok(res, { id, status }, `Loja ${status === 'ativo' ? 'aprovada' : 'bloqueada'}!`);
  } catch (e) { return erro(res, 'Erro ao alterar status', 500); }
}

// GET /admin/clientes — lista clientes
async function listarClientes(req, res) {
  try {
    const result = await pool.query(
      `SELECT id,nome,email,telefone,ios_coins,status,codigo_indicacao,criado_em,
              (SELECT COUNT(*) FROM transacoes WHERE cliente_id=clientes.id) AS total_transacoes
       FROM clientes ORDER BY criado_em DESC`
    );
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao listar clientes', 500); }
}

// PATCH /admin/clientes/:id/status
async function alterarStatusCliente(req, res) {
  const { id } = req.params;
  const { status } = req.body;
  if (!['ativo','bloqueado'].includes(status))
    return erro(res, 'Status inválido');
  try {
    await pool.query('UPDATE clientes SET status=$1 WHERE id=$2', [status, id]);
    return ok(res, { id, status }, `Cliente ${status === 'ativo' ? 'desbloqueado' : 'bloqueado'}!`);
  } catch (e) { return erro(res, 'Erro ao alterar status', 500); }
}

// GET /admin/tarefas — lista todas tarefas
async function listarTarefas(req, res) {
  try {
    const result = await pool.query(
      `SELECT t.*,
              (SELECT COUNT(*) FROM tarefas_concluidas WHERE tarefa_id=t.id) AS total_concluidas
       FROM tarefas t ORDER BY t.criado_em DESC`
    );
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao listar tarefas', 500); }
}

// POST /admin/tarefas — criar tarefa
async function criarTarefa(req, res) {
  const { titulo, descricao, coins, tipo, link } = req.body;
  if (!titulo || !coins || !tipo) return erro(res, 'titulo, coins e tipo são obrigatórios');
  try {
    const id = uuidv4();
    await pool.query(
      'INSERT INTO tarefas (id,titulo,descricao,coins,tipo,link) VALUES ($1,$2,$3,$4,$5,$6)',
      [id, titulo, descricao || null, parseFloat(coins), tipo, link || null]
    );
    return criado(res, { id, titulo, coins, tipo }, 'Tarefa criada!');
  } catch (e) { return erro(res, 'Erro ao criar tarefa', 500); }
}

// PATCH /admin/tarefas/:id — editar tarefa
async function editarTarefa(req, res) {
  const { id } = req.params;
  const { titulo, descricao, coins, tipo, link, ativo } = req.body;
  try {
    await pool.query(
      `UPDATE tarefas SET
         titulo=$1, descricao=$2, coins=$3, tipo=$4, link=$5, ativo=$6
       WHERE id=$7`,
      [titulo, descricao || null, parseFloat(coins), tipo, link || null, ativo, id]
    );
    return ok(res, null, 'Tarefa atualizada!');
  } catch (e) { return erro(res, 'Erro ao editar tarefa', 500); }
}

// GET /admin/premios — lista todos prêmios
async function listarPremios(req, res) {
  try {
    const result = await pool.query('SELECT * FROM premios ORDER BY criado_em DESC');
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao listar prêmios', 500); }
}

// POST /admin/premios — criar prêmio global
async function criarPremio(req, res) {
  const { nome, descricao, custoCoins } = req.body;
  if (!nome || !custoCoins) return erro(res, 'nome e custoCoins obrigatórios');
  try {
    const id = uuidv4();
    await pool.query(
      'INSERT INTO premios (id,nome,descricao,custo_coins) VALUES ($1,$2,$3,$4)',
      [id, nome, descricao || '', parseFloat(custoCoins)]
    );
    return criado(res, { id, nome, custoCoins }, 'Prêmio criado!');
  } catch (e) { return erro(res, 'Erro ao criar prêmio', 500); }
}

// DELETE /admin/premios/:id
async function deletarPremio(req, res) {
  const { id } = req.params;
  try {
    await pool.query('DELETE FROM premios WHERE id=$1', [id]);
    return ok(res, null, 'Prêmio removido!');
  } catch (e) { return erro(res, 'Erro ao remover prêmio', 500); }
}

// GET /admin/relatorio — relatório completo
async function relatorio(req, res) {
  try {
    const [
      topLojas, topClientes, transacoesPorDia, coinsDistribuidos
    ] = await Promise.all([
      pool.query(`
        SELECT l.nome, COUNT(t.id) AS total_transacoes,
               COALESCE(SUM(t.coins),0) AS coins_distribuidos
        FROM lojas l LEFT JOIN transacoes t ON t.loja_id=l.id AND t.tipo='compra'
        GROUP BY l.id, l.nome ORDER BY total_transacoes DESC LIMIT 10`),
      pool.query(`
        SELECT c.nome, c.ios_coins,
               COUNT(t.id) AS total_compras
        FROM clientes c LEFT JOIN transacoes t ON t.cliente_id=c.id AND t.tipo='compra'
        GROUP BY c.id, c.nome, c.ios_coins ORDER BY c.ios_coins DESC LIMIT 10`),
      pool.query(`
        SELECT DATE(criado_em) AS dia, COUNT(*) AS total,
               SUM(CASE WHEN coins > 0 THEN coins ELSE 0 END) AS coins_creditados
        FROM transacoes
        WHERE criado_em >= NOW() - INTERVAL '30 days'
        GROUP BY DATE(criado_em) ORDER BY dia DESC`),
      pool.query(`
        SELECT tipo, COALESCE(SUM(coins),0) AS total
        FROM transacoes GROUP BY tipo ORDER BY total DESC`),
    ]);

    return ok(res, {
      topLojas:        topLojas.rows,
      topClientes:     topClientes.rows,
      transacoesPorDia: transacoesPorDia.rows,
      coinsDistribuidos: coinsDistribuidos.rows,
    });
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao gerar relatório', 500);
  }
}

module.exports = {
  setupAdmin, loginAdmin, dashboard,
  listarLojas, alterarStatusLoja,
  listarClientes, alterarStatusCliente,
  listarTarefas, criarTarefa, editarTarefa,
  listarPremios, criarPremio, deletarPremio,
  relatorio,
};
EOF

# ── routes/admin.js ──────────────────────────────────────────
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

router.post('/login', loginAdmin);

// Todas as rotas abaixo exigem token admin
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

module.exports = router;
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

app.use('/auth',       require('./routes/auth'));
app.use('/cliente',    require('./routes/cliente'));
app.use('/lojas',      require('./routes/loja'));
app.use('/coins',      require('./routes/coins'));
app.use('/premios',    require('./routes/premios'));
app.use('/avaliacoes', require('./routes/avaliacoes'));
app.use('/fidelidade', require('./routes/fidelidade'));
app.use('/tarefas',    require('./routes/tarefas'));
app.use('/admin',      require('./routes/admin'));

app.get('/health', (req, res) => res.json({ status: 'ok', app: 'Cacau Plus' }));
app.use((req, res) => res.status(404).json({ sucesso: false, mensagem: 'Rota não encontrada' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, async () => {
  console.log(`🍫 Cacau Plus backend rodando na porta ${PORT}`);
  await setupAdmin(); // Cria admin padrão se não existir
});
EOF

echo "✅ Backend Admin configurado!"
git add .
git commit -m "feat: painel admin completo"
git push
echo "✅ Push feito! Aguarde o Render fazer deploy."
