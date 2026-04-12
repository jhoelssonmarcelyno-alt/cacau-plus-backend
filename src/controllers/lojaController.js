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
