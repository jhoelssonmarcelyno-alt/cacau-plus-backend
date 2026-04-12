// src/controllers/avaliacaoController.js

const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, criado, erro } = require('../utils/resposta');

// POST /avaliacoes
async function criarAvaliacao(req, res) {
  const clienteId = req.usuario.id;
  const { lojaId, estrelas, comentario } = req.body;

  if (!lojaId || !estrelas) return erro(res, 'lojaId e estrelas são obrigatórios');
  if (estrelas < 1 || estrelas > 5) return erro(res, 'Estrelas deve ser entre 1 e 5');

  try {
    // Verifica se comprou na loja
    const comprou = await pool.query(
      `SELECT id FROM transacoes
       WHERE cliente_id = $1 AND loja_id = $2 AND tipo = 'compra' LIMIT 1`,
      [clienteId, lojaId]
    );
    if (comprou.rows.length === 0) {
      return erro(res, 'Você só pode avaliar lojas onde já realizou uma compra.', 403);
    }

    // Verifica se já avaliou — se sim, atualiza
    const jaAvaliou = await pool.query(
      'SELECT id FROM avaliacoes WHERE cliente_id = $1 AND loja_id = $2',
      [clienteId, lojaId]
    );
    if (jaAvaliou.rows.length > 0) {
      await pool.query(
        'UPDATE avaliacoes SET estrelas=$1, comentario=$2 WHERE cliente_id=$3 AND loja_id=$4',
        [estrelas, comentario || null, clienteId, lojaId]
      );
      return ok(res, null, 'Avaliação atualizada!');
    }

    const id = uuidv4();
    await pool.query(
      'INSERT INTO avaliacoes (id, cliente_id, loja_id, estrelas, comentario) VALUES ($1,$2,$3,$4,$5)',
      [id, clienteId, lojaId, estrelas, comentario || null]
    );
    return criado(res, { id }, 'Avaliação enviada!');
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao salvar avaliação', 500);
  }
}

// GET /avaliacoes/loja/:lojaId
async function listarAvaliacoesDaLoja(req, res) {
  const { lojaId } = req.params;
  try {
    const result = await pool.query(
      `SELECT a.id, a.estrelas, a.comentario, a.criado_em,
              c.nome AS cliente_nome
       FROM avaliacoes a
       JOIN clientes c ON c.id = a.cliente_id
       WHERE a.loja_id = $1
       ORDER BY a.criado_em DESC`,
      [lojaId]
    );
    const media = result.rows.length > 0
      ? result.rows.reduce((acc, r) => acc + r.estrelas, 0) / result.rows.length
      : 0;
    return ok(res, {
      media: parseFloat(media.toFixed(1)),
      total: result.rows.length,
      avaliacoes: result.rows,
    });
  } catch (e) {
    return erro(res, 'Erro ao buscar avaliações', 500);
  }
}

// GET /avaliacoes/minhas
async function minhasAvaliacoes(req, res) {
  const clienteId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT a.id, a.estrelas, a.comentario, a.criado_em, l.nome AS loja_nome
       FROM avaliacoes a
       JOIN lojas l ON l.id = a.loja_id
       WHERE a.cliente_id = $1
       ORDER BY a.criado_em DESC`,
      [clienteId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar avaliações', 500);
  }
}

// DELETE /avaliacoes/:id
async function deletarAvaliacao(req, res) {
  const clienteId = req.usuario.id;
  const { id } = req.params;
  try {
    const result = await pool.query(
      'DELETE FROM avaliacoes WHERE id=$1 AND cliente_id=$2 RETURNING id',
      [id, clienteId]
    );
    if (result.rows.length === 0) return erro(res, 'Avaliação não encontrada', 404);
    return ok(res, null, 'Avaliação removida.');
  } catch (e) {
    return erro(res, 'Erro ao remover avaliação', 500);
  }
}

module.exports = { criarAvaliacao, listarAvaliacoesDaLoja, minhasAvaliacoes, deletarAvaliacao };