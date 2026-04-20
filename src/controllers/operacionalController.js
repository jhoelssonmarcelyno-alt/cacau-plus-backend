const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// ── LOG DE ATIVIDADES ─────────────────────────────────────────

async function registrarLog(adminId, acao, detalhes, ip) {
  try {
    await pool.query(
      'INSERT INTO admin_logs (id,admin_id,acao,detalhes,ip) VALUES ($1,$2,$3,$4,$5)',
      [uuidv4(), adminId, acao, detalhes || null, ip || null]
    );
  } catch (e) {
    console.error('Erro ao registrar log:', e.message);
  }
}

async function listarLogs(req, res) {
  try {
    const result = await pool.query(
      `SELECT al.id, al.acao, al.detalhes, al.ip, al.criado_em,
              a.nome AS admin_nome
       FROM admin_logs al
       JOIN admins a ON a.id = al.admin_id
       ORDER BY al.criado_em DESC LIMIT 100`
    );
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao buscar logs', 500); }
}

// ── CLIENTES INATIVOS ─────────────────────────────────────────

async function clientesInativos(req, res) {
  const dias = parseInt(req.query.dias) || 30;
  try {
    const result = await pool.query(
      `SELECT c.id, c.nome, c.email, c.telefone, c.ios_coins, c.nivel,
              c.criado_em,
              MAX(t.criado_em) AS ultima_compra,
              COUNT(t.id) AS total_compras
       FROM clientes c
       LEFT JOIN transacoes t ON t.cliente_id = c.id AND t.tipo = 'compra'
       WHERE c.status = 'ativo'
       GROUP BY c.id, c.nome, c.email, c.telefone, c.ios_coins, c.nivel, c.criado_em
       HAVING MAX(t.criado_em) < NOW() - INTERVAL '${dias} days'
          OR MAX(t.criado_em) IS NULL
       ORDER BY ultima_compra ASC NULLS FIRST
       LIMIT 100`
    );
    return ok(res, result.rows);
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao buscar inativos', 500);
  }
}

// ── EXPORTAÇÃO CSV ────────────────────────────────────────────

async function exportarClientesCSV(req, res) {
  try {
    const result = await pool.query(
      `SELECT c.numero, c.nome, c.email, c.telefone,
              c.ios_coins, c.nivel, c.status,
              c.codigo_indicacao, c.criado_em,
              COUNT(t.id) AS total_compras
       FROM clientes c
       LEFT JOIN transacoes t ON t.cliente_id = c.id AND t.tipo = 'compra'
       GROUP BY c.id ORDER BY c.numero ASC`
    );

    const header = 'Numero,Nome,Email,Telefone,IOS Coins,Nivel,Status,Codigo Indicacao,Cadastro,Total Compras\n';
    const linhas = result.rows.map(r =>
      `${r.numero},"${r.nome}","${r.email}","${r.telefone || ''}",${r.ios_coins},${r.nivel},${r.status},"${r.codigo_indicacao || ''}","${new Date(r.criado_em).toLocaleDateString('pt-BR')}",${r.total_compras}`
    ).join('\n');

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename=clientes_cacau_plus.csv');
    res.send('\uFEFF' + header + linhas); // BOM para Excel ler corretamente
  } catch (e) {
    return erro(res, 'Erro ao exportar', 500);
  }
}

async function exportarLojasCSV(req, res) {
  try {
    const result = await pool.query(
      `SELECT l.numero, l.nome, l.email, l.telefone, l.endereco,
              l.coins_por_real, l.desconto_max_pct, l.status, l.criado_em,
              COUNT(t.id) AS total_transacoes
       FROM lojas l
       LEFT JOIN transacoes t ON t.loja_id = l.id
       GROUP BY l.id ORDER BY l.numero ASC`
    );

    const header = 'Numero,Nome,Email,Telefone,Endereco,Coins/Real,Desconto Max,Status,Cadastro,Total Transacoes\n';
    const linhas = result.rows.map(r =>
      `${r.numero},"${r.nome}","${r.email}","${r.telefone || ''}","${r.endereco || ''}",${r.coins_por_real},${r.desconto_max_pct}%,${r.status},"${new Date(r.criado_em).toLocaleDateString('pt-BR')}",${r.total_transacoes}`
    ).join('\n');

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename=lojas_cacau_plus.csv');
    res.send('\uFEFF' + header + linhas);
  } catch (e) {
    return erro(res, 'Erro ao exportar', 500);
  }
}

async function exportarTransacoesCSV(req, res) {
  try {
    const result = await pool.query(
      `SELECT t.id, c.nome AS cliente, l.nome AS loja,
              t.coins, t.tipo, t.descricao, t.criado_em
       FROM transacoes t
       JOIN clientes c ON c.id = t.cliente_id
       LEFT JOIN lojas l ON l.id = t.loja_id
       ORDER BY t.criado_em DESC LIMIT 5000`
    );

    const header = 'ID,Cliente,Loja,Coins,Tipo,Descricao,Data\n';
    const linhas = result.rows.map(r =>
      `"${r.id}","${r.cliente}","${r.loja || ''}",${r.coins},${r.tipo},"${r.descricao || ''}","${new Date(r.criado_em).toLocaleDateString('pt-BR')}"`
    ).join('\n');

    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename=transacoes_cacau_plus.csv');
    res.send('\uFEFF' + header + linhas);
  } catch (e) {
    return erro(res, 'Erro ao exportar', 500);
  }
}

// ── SUPORTE ───────────────────────────────────────────────────

async function abrirTicket(req, res) {
  const { assunto, mensagem } = req.body;
  if (!assunto || !mensagem) return erro(res, 'assunto e mensagem obrigatórios');

  const clienteId = req.usuario?.id;
  const tipo      = req.usuario?.tipo || 'cliente';

  try {
    // Busca dados do usuário
    let nome = '', email = '', lojaId = null;
    if (tipo === 'cliente') {
      const r = await pool.query('SELECT nome, email FROM clientes WHERE id=$1', [clienteId]);
      nome  = r.rows[0]?.nome || '';
      email = r.rows[0]?.email || '';
    } else if (tipo === 'loja') {
      const r = await pool.query('SELECT nome, email FROM lojas WHERE id=$1', [clienteId]);
      nome   = r.rows[0]?.nome || '';
      email  = r.rows[0]?.email || '';
      lojaId = clienteId;
    }

    const id = uuidv4();
    await pool.query(
      `INSERT INTO suporte (id,cliente_id,loja_id,tipo,nome,email,assunto,mensagem)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [id, tipo === 'cliente' ? clienteId : null, lojaId,
       tipo, nome, email, assunto, mensagem]
    );
    return ok(res, { id }, 'Ticket aberto! Responderemos em breve.');
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao abrir ticket', 500);
  }
}

async function listarTickets(req, res) {
  const { status } = req.query;
  try {
    const result = await pool.query(
      `SELECT * FROM suporte
       ${status ? `WHERE status='${status}'` : ''}
       ORDER BY criado_em DESC LIMIT 100`
    );
    return ok(res, result.rows);
  } catch (e) { return erro(res, 'Erro ao buscar tickets', 500); }
}

async function responderTicket(req, res) {
  const adminId = req.usuario.id;
  const { id }  = req.params;
  const { resposta, status } = req.body;
  if (!resposta) return erro(res, 'Resposta obrigatória');

  try {
    const ticket = await pool.query('SELECT * FROM suporte WHERE id=$1', [id]);
    if (!ticket.rows.length) return erro(res, 'Ticket não encontrado', 404);

    await pool.query(
      `UPDATE suporte SET resposta=$1, status=$2, respondido_em=NOW() WHERE id=$3`,
      [resposta, status || 'respondido', id]
    );

    // Notifica o cliente
    const t = ticket.rows[0];
    if (t.cliente_id) {
      await pool.query(
        `INSERT INTO notificacoes (id,cliente_id,titulo,mensagem,tipo)
         VALUES ($1,$2,$3,$4,'geral')`,
        [uuidv4(), t.cliente_id,
         '💬 Suporte respondeu seu ticket',
         resposta.substring(0, 100)]
      );
    }

    await registrarLog(adminId, 'RESPONDER_TICKET',
      `Ticket #${id.substring(0,8)} respondido`);

    return ok(res, null, 'Ticket respondido!');
  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao responder ticket', 500);
  }
}

module.exports = {
  registrarLog, listarLogs,
  clientesInativos,
  exportarClientesCSV, exportarLojasCSV, exportarTransacoesCSV,
  abrirTicket, listarTickets, responderTicket,
};
