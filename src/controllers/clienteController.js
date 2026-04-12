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
