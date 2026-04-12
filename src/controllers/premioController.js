// src/controllers/premioController.js
// CRUD de prêmios disponíveis para resgate

const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, criado, erro } = require('../utils/resposta');

// GET /premios  (público)
async function listar(req, res) {
  try {
    const result = await pool.query('SELECT * FROM premios ORDER BY custo_coins');
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao listar prêmios', 500);
  }
}

// POST /premios  (loja autenticada cria prêmio)
async function criar(req, res) {
  const { nome, descricao, custoCoins } = req.body;
  if (!nome || !custoCoins) return erro(res, 'nome e custoCoins obrigatórios');

  try {
    const id = uuidv4();
    await pool.query(
      'INSERT INTO premios (id, nome, descricao, custo_coins, loja_id) VALUES ($1,$2,$3,$4,$5)',
      [id, nome, descricao || '', parseFloat(custoCoins), req.usuario.id]
    );
    return criado(res, { id, nome, custoCoins: parseFloat(custoCoins) });
  } catch (e) {
    return erro(res, 'Erro ao criar prêmio', 500);
  }
}

module.exports = { listar, criar };
