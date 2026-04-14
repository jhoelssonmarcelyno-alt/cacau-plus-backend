const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, criado, erro } = require('../utils/resposta');

// ── Garante que admin tem registro em admin_coins ────────────
async function garantirSaldo(adminId, client) {
  await client.query(
    `INSERT INTO admin_coins (id, admin_id, saldo)
     VALUES ($1,$2,0) ON CONFLICT (admin_id) DO NOTHING`,
    [uuidv4(), adminId]
  );
}

// GET /admin/coins/saldo — saldo do admin
async function saldoAdmin(req, res) {
  const adminId = req.usuario.id;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await garantirSaldo(adminId, client);
    await client.query('COMMIT');
    const result = await pool.query(
      'SELECT saldo FROM admin_coins WHERE admin_id=$1', [adminId]
    );
    return ok(res, { saldo: parseFloat(result.rows[0]?.saldo ?? 0) });
  } catch (e) {
    await client.query('ROLLBACK');
    return erro(res, 'Erro ao buscar saldo', 500);
  } finally {
    client.release();
  }
}

// POST /admin/coins/gerar — admin gera coins para si
async function gerarCoins(req, res) {
  const adminId = req.usuario.id;
  const { quantidade } = req.body;
  if (!quantidade || quantidade <= 0) return erro(res, 'Quantidade inválida');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await garantirSaldo(adminId, client);

    await client.query(
      `UPDATE admin_coins SET saldo = saldo + $1, atualizado_em = NOW()
       WHERE admin_id = $2`,
      [quantidade, adminId]
    );

    await client.query(
      `INSERT INTO admin_transacoes (id, admin_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'gerar','Coins gerados pelo admin')`,
      [uuidv4(), adminId, quantidade]
    );

    await client.query('COMMIT');

    const novoSaldo = await pool.query(
      'SELECT saldo FROM admin_coins WHERE admin_id=$1', [adminId]
    );
    return ok(res, {
      saldo: parseFloat(novoSaldo.rows[0].saldo),
      coinsGerados: quantidade,
    }, `${quantidade} coins gerados com sucesso!`);
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao gerar coins', 500);
  } finally {
    client.release();
  }
}

// POST /admin/coins/enviar — envia coins para cliente específico
async function enviarCoins(req, res) {
  const adminId = req.usuario.id;
  const { clienteId, quantidade, descricao } = req.body;
  if (!clienteId || !quantidade || quantidade <= 0)
    return erro(res, 'clienteId e quantidade são obrigatórios');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await garantirSaldo(adminId, client);

    // Verifica saldo admin
    const resSaldo = await client.query(
      'SELECT saldo FROM admin_coins WHERE admin_id=$1', [adminId]
    );
    const saldo = parseFloat(resSaldo.rows[0]?.saldo ?? 0);
    if (saldo < quantidade) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Você tem ${saldo.toFixed(0)} coins.`);
    }

    // Verifica cliente
    const resCliente = await client.query(
      'SELECT nome FROM clientes WHERE id=$1', [clienteId]
    );
    if (!resCliente.rows.length) {
      await client.query('ROLLBACK');
      return erro(res, 'Cliente não encontrado', 404);
    }
    const nomeCliente = resCliente.rows[0].nome;

    // Debita do admin
    await client.query(
      'UPDATE admin_coins SET saldo = saldo - $1, atualizado_em = NOW() WHERE admin_id=$2',
      [quantidade, adminId]
    );

    // Credita no cliente
    await client.query(
      'UPDATE clientes SET ios_coins = ios_coins + $1 WHERE id=$2',
      [quantidade, clienteId]
    );

    // Registra transações
    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'boas_vindas',$4)`,
      [uuidv4(), clienteId, quantidade,
       descricao || `Presente do administrador Cacau Plus!`]
    );
    await client.query(
      `INSERT INTO admin_transacoes (id, admin_id, cliente_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,$4,'envio',$5)`,
      [uuidv4(), adminId, clienteId, -quantidade,
       `Enviado para ${nomeCliente}`]
    );

    await client.query('COMMIT');

    const novoSaldo = await pool.query(
      'SELECT saldo FROM admin_coins WHERE admin_id=$1', [adminId]
    );
    return ok(res, {
      nomeCliente,
      quantidade,
      saldoAdmin: parseFloat(novoSaldo.rows[0].saldo),
    }, `${quantidade} coins enviados para ${nomeCliente}!`);

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao enviar coins', 500);
  } finally {
    client.release();
  }
}

// POST /admin/sorteio/realizar — sorteia ganhadores
async function realizarSorteio(req, res) {
  const adminId = req.usuario.id;
  const { quantGanhadores, coinsPorGanhador } = req.body;

  if (!quantGanhadores || quantGanhadores < 1)
    return erro(res, 'Informe a quantidade de ganhadores');
  if (!coinsPorGanhador || coinsPorGanhador <= 0)
    return erro(res, 'Informe os coins por ganhador');

  const totalCoins = quantGanhadores * coinsPorGanhador;
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    await garantirSaldo(adminId, client);

    // Verifica saldo admin
    const resSaldo = await client.query(
      'SELECT saldo FROM admin_coins WHERE admin_id=$1', [adminId]
    );
    const saldo = parseFloat(resSaldo.rows[0]?.saldo ?? 0);
    if (saldo < totalCoins) {
      await client.query('ROLLBACK');
      return erro(res,
        `Saldo insuficiente. Você tem ${saldo.toFixed(0)} coins e precisa de ${totalCoins}.`);
    }

    // Busca todos os clientes ativos
    const resClientes = await client.query(
      `SELECT id, nome FROM clientes WHERE status='ativo' ORDER BY RANDOM() LIMIT $1`,
      [quantGanhadores]
    );

    if (resClientes.rows.length === 0) {
      await client.query('ROLLBACK');
      return erro(res, 'Nenhum cliente ativo para sortear');
    }

    const ganhadores = resClientes.rows;
    const sorteioId = uuidv4();

    // Cria registro do sorteio
    await client.query(
      `INSERT INTO sorteios (id, admin_id, ganhadores, premio_coins)
       VALUES ($1,$2,$3,$4)`,
      [sorteioId, adminId, ganhadores.length, coinsPorGanhador]
    );

    // Processa cada ganhador
    for (const g of ganhadores) {
      await client.query(
        'UPDATE clientes SET ios_coins = ios_coins + $1 WHERE id=$2',
        [coinsPorGanhador, g.id]
      );
      await client.query(
        `INSERT INTO sorteio_ganhadores (id, sorteio_id, cliente_id, coins)
         VALUES ($1,$2,$3,$4)`,
        [uuidv4(), sorteioId, g.id, coinsPorGanhador]
      );
      await client.query(
        `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
         VALUES ($1,$2,$3,'boas_vindas','🎉 Você ganhou o sorteio Cacau Plus!')`,
        [uuidv4(), g.id, coinsPorGanhador]
      );
    }

    // Debita total do admin
    await client.query(
      'UPDATE admin_coins SET saldo = saldo - $1, atualizado_em = NOW() WHERE admin_id=$2',
      [totalCoins, adminId]
    );
    await client.query(
      `INSERT INTO admin_transacoes (id, admin_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'sorteio',$4)`,
      [uuidv4(), adminId, -totalCoins,
       `Sorteio: ${ganhadores.length} ganhadores × ${coinsPorGanhador} coins`]
    );

    await client.query('COMMIT');

    const novoSaldo = await pool.query(
      'SELECT saldo FROM admin_coins WHERE admin_id=$1', [adminId]
    );
    return ok(res, {
      sorteioId,
      ganhadores: ganhadores.map(g => ({ id: g.id, nome: g.nome, coins: coinsPorGanhador })),
      totalDistribuido: totalCoins,
      saldoAdmin: parseFloat(novoSaldo.rows[0].saldo),
    }, `Sorteio realizado! ${ganhadores.length} ganhadores, ${totalCoins} coins distribuídos!`);

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao realizar sorteio', 500);
  } finally {
    client.release();
  }
}

// GET /admin/sorteio/historico
async function historicoSorteios(req, res) {
  try {
    const result = await pool.query(
      `SELECT s.id, s.ganhadores, s.premio_coins, s.criado_em,
              json_agg(json_build_object('nome', c.nome, 'coins', sg.coins)) AS lista_ganhadores
       FROM sorteios s
       JOIN sorteio_ganhadores sg ON sg.sorteio_id = s.id
       JOIN clientes c ON c.id = sg.cliente_id
       GROUP BY s.id, s.ganhadores, s.premio_coins, s.criado_em
       ORDER BY s.criado_em DESC LIMIT 20`
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar histórico', 500);
  }
}

// GET /admin/coins/historico
async function historicoAdmin(req, res) {
  const adminId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT at.id, at.coins, at.tipo, at.descricao, at.criado_em,
              c.nome AS cliente_nome
       FROM admin_transacoes at
       LEFT JOIN clientes c ON c.id = at.cliente_id
       WHERE at.admin_id = $1
       ORDER BY at.criado_em DESC LIMIT 50`,
      [adminId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar histórico', 500);
  }
}

module.exports = {
  saldoAdmin, gerarCoins, enviarCoins,
  realizarSorteio, historicoSorteios, historicoAdmin,
};
