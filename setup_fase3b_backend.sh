#!/bin/bash
# Execute dentro de: /f/CACAU PLUS/Cacau_Plus/mobile/backend
# bash setup_fase3b_backend.sh

echo "🍫 Configurando backend Fase 3B..."

npm install firebase-admin 2>/dev/null

# ── firebase.js ──────────────────────────────────────────────
cat > src/config/firebase.js << 'EOF'
// src/config/firebase.js
// Inicializa Firebase Admin SDK para envio de push notifications

let admin;

function getAdmin() {
  if (admin) return admin;
  try {
    admin = require('firebase-admin');
    const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT
      ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
      : null;

    if (!serviceAccount) {
      console.warn('⚠️  FIREBASE_SERVICE_ACCOUNT não configurado — push desativado');
      return null;
    }

    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
    }
    return admin;
  } catch (e) {
    console.error('Erro ao inicializar Firebase:', e.message);
    return null;
  }
}

async function enviarPush(tokens, titulo, mensagem, dados = {}) {
  const a = getAdmin();
  if (!a || !tokens.length) return;

  try {
    const message = {
      notification: { title: titulo, body: mensagem },
      data: { ...dados },
      tokens,
    };
    const res = await a.messaging().sendEachForMulticast(message);
    console.log(`Push enviado: ${res.successCount} ok, ${res.failureCount} falhas`);
    return res;
  } catch (e) {
    console.error('Erro ao enviar push:', e.message);
  }
}

module.exports = { enviarPush };
EOF

# ── bannersController.js ─────────────────────────────────────
cat > src/controllers/bannersController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, criado, erro } = require('../utils/resposta');

// GET /banners — público, lista banners ativos
async function listarBanners(req, res) {
  try {
    const result = await pool.query(
      'SELECT * FROM banners WHERE ativo=true ORDER BY ordem ASC'
    );
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao buscar banners', 500); }
}

// GET /admin/banners
async function listarBannersAdmin(req, res) {
  try {
    const result = await pool.query('SELECT * FROM banners ORDER BY ordem ASC');
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao buscar banners', 500); }
}

// POST /admin/banners
async function criarBanner(req, res) {
  const { titulo, subtitulo, corFundo, corTexto, emoji, linkTela, ordem } = req.body;
  if (!titulo) return erro(res, 'Título obrigatório');
  try {
    const id = uuidv4();
    await pool.query(
      `INSERT INTO banners (id,titulo,subtitulo,cor_fundo,cor_texto,emoji,link_tela,ordem)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [id, titulo, subtitulo || null,
       corFundo || '#3E2723', corTexto || '#FFFFFF',
       emoji || '🍫', linkTela || null, ordem || 0]
    );
    return criado(res, { id, titulo }, 'Banner criado!');
  } catch (e) { return erro(res, 'Erro ao criar banner', 500); }
}

// PATCH /admin/banners/:id
async function editarBanner(req, res) {
  const { id } = req.params;
  const { titulo, subtitulo, corFundo, corTexto, emoji, linkTela, ordem, ativo } = req.body;
  try {
    await pool.query(
      `UPDATE banners SET titulo=$1,subtitulo=$2,cor_fundo=$3,cor_texto=$4,
       emoji=$5,link_tela=$6,ordem=$7,ativo=$8 WHERE id=$9`,
      [titulo, subtitulo, corFundo, corTexto, emoji, linkTela, ordem, ativo, id]
    );
    return ok(res, null, 'Banner atualizado!');
  } catch (e) { return erro(res, 'Erro ao editar banner', 500); }
}

// DELETE /admin/banners/:id
async function deletarBanner(req, res) {
  const { id } = req.params;
  try {
    await pool.query('DELETE FROM banners WHERE id=$1', [id]);
    return ok(res, null, 'Banner removido!');
  } catch (e) { return erro(res, 'Erro ao remover banner', 500); }
}

module.exports = { listarBanners, listarBannersAdmin, criarBanner, editarBanner, deletarBanner };
EOF

# ── pushController.js ────────────────────────────────────────
cat > src/controllers/pushController.js << 'EOF'
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');
const { enviarPush } = require('../config/firebase');

// POST /push/registrar — cliente registra token FCM
async function registrarToken(req, res) {
  const clienteId = req.usuario.id;
  const { token } = req.body;
  if (!token) return erro(res, 'Token obrigatório');
  try {
    await pool.query(
      `INSERT INTO fcm_tokens (id, cliente_id, token)
       VALUES ($1,$2,$3)
       ON CONFLICT (token) DO UPDATE SET cliente_id=$2`,
      [uuidv4(), clienteId, token]
    );
    return ok(res, null, 'Token registrado!');
  } catch (e) { return erro(res, 'Erro ao registrar token', 500); }
}

// POST /admin/push/enviar — admin envia push para todos ou cliente específico
async function enviarPushAdmin(req, res) {
  const { clienteId, titulo, mensagem } = req.body;
  if (!titulo || !mensagem) return erro(res, 'titulo e mensagem obrigatórios');

  try {
    let tokens = [];
    if (clienteId) {
      const result = await pool.query(
        'SELECT token FROM fcm_tokens WHERE cliente_id=$1', [clienteId]
      );
      tokens = result.rows.map(r => r.token);
    } else {
      const result = await pool.query(
        `SELECT ft.token FROM fcm_tokens ft
         JOIN clientes c ON c.id = ft.cliente_id
         WHERE c.status='ativo'`
      );
      tokens = result.rows.map(r => r.token);
    }

    if (tokens.length === 0) {
      return ok(res, { enviados: 0 }, 'Nenhum dispositivo registrado ainda.');
    }

    await enviarPush(tokens, titulo, mensagem);
    return ok(res, { enviados: tokens.length },
      `Push enviado para ${tokens.length} dispositivo(s)!`);
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao enviar push', 500);
  }
}

module.exports = { registrarToken, enviarPushAdmin };
EOF

# ── routes/banners.js ────────────────────────────────────────
cat > src/routes/banners.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { listarBanners } = require('../controllers/bannersController');

router.get('/', listarBanners);
module.exports = router;
EOF

# ── routes/push.js ───────────────────────────────────────────
cat > src/routes/push.js << 'EOF'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { registrarToken } = require('../controllers/pushController');

router.post('/registrar', autenticar, apenasCliente, registrarToken);
module.exports = router;
EOF

# ── routes/admin.js — adiciona banners e push ────────────────
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
const { listarBannersAdmin, criarBanner, editarBanner, deletarBanner } = require('../controllers/bannersController');
const { enviarPushAdmin } = require('../controllers/pushController');

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
router.get('/banners',                listarBannersAdmin);
router.post('/banners',               criarBanner);
router.patch('/banners/:id',          editarBanner);
router.delete('/banners/:id',         deletarBanner);
router.post('/push/enviar',           enviarPushAdmin);

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

app.use('/auth',         require('./routes/auth'));
app.use('/cliente',      require('./routes/cliente'));
app.use('/lojas',        require('./routes/loja'));
app.use('/coins',        require('./routes/coins'));
app.use('/premios',      require('./routes/premios'));
app.use('/avaliacoes',   require('./routes/avaliacoes'));
app.use('/fidelidade',   require('./routes/fidelidade'));
app.use('/tarefas',      require('./routes/tarefas'));
app.use('/campanhas',    require('./routes/campanhas'));
app.use('/notificacoes', require('./routes/notificacoes'));
app.use('/banners',      require('./routes/banners'));
app.use('/push',         require('./routes/push'));
app.use('/admin',        require('./routes/admin'));
app.use('/admin',        require('./routes/adminCoins'));

app.get('/health', (req, res) => res.json({ status: 'ok', app: 'Cacau Plus' }));
app.use((req, res) => res.status(404).json({ sucesso: false, mensagem: 'Rota não encontrada' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, async () => {
  console.log(`🍫 Cacau Plus backend rodando na porta ${PORT}`);
  await setupAdmin();
});
EOF

echo "✅ Backend Fase 3B configurado!"
git add .
git commit -m "feat: banners, push notifications FCM"
git push
echo "✅ Push feito!"