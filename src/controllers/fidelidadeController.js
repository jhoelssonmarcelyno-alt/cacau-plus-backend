const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, criado, erro } = require('../utils/resposta');

// Registra visita do cliente na loja (chamado automaticamente na compra)
async function registrarVisita(clienteId, lojaId, client) {
  await client.query(
    'INSERT INTO visitas (id, cliente_id, loja_id) VALUES ($1,$2,$3)',
    [uuidv4(), clienteId, lojaId]
  );
}

// Verifica se cliente ganhou brinde após visita
async function verificarBrinde(clienteId, lojaId, client) {
  const resLoja = await client.query(
    'SELECT fidelidade_ativo, fidelidade_visitas, fidelidade_brinde FROM lojas WHERE id=$1',
    [lojaId]
  );
  const loja = resLoja.rows[0];
  if (!loja.fidelidade_ativo || !loja.fidelidade_brinde) return null;

  const resVisitas = await client.query(
    'SELECT COUNT(*) FROM visitas WHERE cliente_id=$1 AND loja_id=$2',
    [clienteId, lojaId]
  );
  const total = parseInt(resVisitas.rows[0].count);
  const meta  = loja.fidelidade_visitas;

  if (total % meta === 0) {
    await client.query(
      'INSERT INTO brindes_resgatados (id, cliente_id, loja_id, brinde) VALUES ($1,$2,$3,$4)',
      [uuidv4(), clienteId, lojaId, loja.fidelidade_brinde]
    );
    return loja.fidelidade_brinde;
  }
  return null;
}

// GET /fidelidade/progresso/:lojaId — cliente vê progresso na loja
async function progressoCliente(req, res) {
  const clienteId = req.usuario.id;
  const { lojaId } = req.params;
  try {
    const resLoja = await pool.query(
      'SELECT nome, fidelidade_ativo, fidelidade_visitas, fidelidade_brinde FROM lojas WHERE id=$1',
      [lojaId]
    );
    if (!resLoja.rows.length) return erro(res, 'Loja não encontrada', 404);
    const loja = resLoja.rows[0];

    const resVisitas = await pool.query(
      'SELECT COUNT(*) FROM visitas WHERE cliente_id=$1 AND loja_id=$2',
      [clienteId, lojaId]
    );
    const totalVisitas = parseInt(resVisitas.rows[0].count);
    const meta = loja.fidelidade_visitas;
    const progresso = totalVisitas % meta;

    return ok(res, {
      lojaNome:         loja.nome,
      fidelidadeAtivo:  loja.fidelidade_ativo,
      meta,
      totalVisitas,
      progresso,
      faltam:           meta - progresso,
      brinde:           loja.fidelidade_brinde,
    });
  } catch (e) {
    return erro(res, 'Erro ao buscar progresso', 500);
  }
}

// GET /fidelidade/clientes — loja vê clientes fidelizados
async function clientesDaLoja(req, res) {
  const lojaId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT c.id, c.nome, c.telefone, c.email,
              COUNT(v.id) AS total_visitas,
              MAX(v.criado_em) AS ultima_visita,
              c.ios_coins
       FROM visitas v
       JOIN clientes c ON c.id = v.cliente_id
       WHERE v.loja_id = $1
       GROUP BY c.id, c.nome, c.telefone, c.email, c.ios_coins
       ORDER BY total_visitas DESC`,
      [lojaId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar clientes', 500);
  }
}

// GET /fidelidade/brindes — loja vê brindes concedidos
async function brindesDaLoja(req, res) {
  const lojaId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT b.id, b.brinde, b.criado_em, c.nome AS cliente_nome
       FROM brindes_resgatados b
       JOIN clientes c ON c.id = b.cliente_id
       WHERE b.loja_id = $1
       ORDER BY b.criado_em DESC LIMIT 50`,
      [lojaId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar brindes', 500);
  }
}

// PATCH /fidelidade/configurar — loja configura fidelidade
async function configurarFidelidade(req, res) {
  const lojaId = req.usuario.id;
  const { ativo, visitas, brinde } = req.body;
  if (ativo && (!visitas || visitas < 2)) {
    return erro(res, 'Informe quantas visitas para o brinde (mínimo 2)');
  }
  if (ativo && !brinde) {
    return erro(res, 'Informe o brinde');
  }
  try {
    await pool.query(
      'UPDATE lojas SET fidelidade_ativo=$1, fidelidade_visitas=$2, fidelidade_brinde=$3 WHERE id=$4',
      [ativo, visitas || 10, brinde || null, lojaId]
    );
    return ok(res, { ativo, visitas, brinde }, 'Fidelidade configurada!');
  } catch (e) {
    return erro(res, 'Erro ao configurar fidelidade', 500);
  }
}

// GET /fidelidade/transacoes — loja vê histórico de transações
async function transacoesDaLoja(req, res) {
  const lojaId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT t.id, t.coins, t.tipo, t.descricao, t.criado_em,
              c.nome AS cliente_nome
       FROM transacoes t
       JOIN clientes c ON c.id = t.cliente_id
       WHERE t.loja_id = $1
       ORDER BY t.criado_em DESC LIMIT 100`,
      [lojaId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar transações', 500);
  }
}

module.exports = {
  registrarVisita, verificarBrinde,
  progressoCliente, clientesDaLoja, brindesDaLoja,
  configurarFidelidade, transacoesDaLoja,
};
