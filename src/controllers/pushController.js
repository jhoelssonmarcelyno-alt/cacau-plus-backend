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
