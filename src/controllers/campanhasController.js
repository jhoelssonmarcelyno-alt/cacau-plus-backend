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
