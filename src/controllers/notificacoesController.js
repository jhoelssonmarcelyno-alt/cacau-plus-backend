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
