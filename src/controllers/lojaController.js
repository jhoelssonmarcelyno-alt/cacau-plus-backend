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
