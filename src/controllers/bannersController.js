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
