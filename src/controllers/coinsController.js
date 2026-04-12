// src/controllers/coinsController.js
// Lógica de crédito de coins por compra (loja credita no cliente)

const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// POST /coins/creditar-compra
// Loja autenticada informa o cliente e o valor da compra
async function creditarCompra(req, res) {
  const { clienteId, valorCompra } = req.body;
  const lojaId = req.usuario.id;

  if (!clienteId || !valorCompra || isNaN(valorCompra) || valorCompra <= 0) {
    return erro(res, 'clienteId e valorCompra são obrigatórios');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Busca taxa da loja
    const resLoja = await client.query(
      'SELECT nome, coins_por_real FROM lojas WHERE id = $1', [lojaId]
    );
    if (resLoja.rows.length === 0) {
      await client.query('ROLLBACK');
      return erro(res, 'Loja não encontrada', 404);
    }

    const { nome: nomeL, coins_por_real } = resLoja.rows[0];
    const coinsGanhos = parseFloat(valorCompra) * parseFloat(coins_por_real);

    // Verifica cliente
    const resCliente = await client.query(
      'SELECT nome FROM clientes WHERE id = $1', [clienteId]
    );
    if (resCliente.rows.length === 0) {
      await client.query('ROLLBACK');
      return erro(res, 'Cliente não encontrado', 404);
    }

    // Credita coins
    await client.query(
      'UPDATE clientes SET ios_coins = ios_coins + $1 WHERE id = $2',
      [coinsGanhos, clienteId]
    );

    // Registra transação
    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, loja_id, descricao)
       VALUES ($1,$2,$3,'compra',$4,$5)`,
      [uuidv4(), clienteId, coinsGanhos, lojaId, `Compra em ${nomeL}`]
    );

    await client.query('COMMIT');

    return ok(res, {
      coinsGanhos: parseFloat(coinsGanhos.toFixed(2)),
      nomeCliente: resCliente.rows[0].nome,
    }, `${coinsGanhos.toFixed(0)} IOS Coins creditados!`);

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao creditar coins', 500);
  } finally {
    client.release();
  }
}

// POST /coins/resgatar
// Cliente resgata prêmio consumindo coins
async function resgatar(req, res) {
  const { premioId } = req.body;
  const clienteId = req.usuario.id;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const resPremio = await client.query(
      'SELECT * FROM premios WHERE id = $1', [premioId]
    );
    if (resPremio.rows.length === 0) {
      await client.query('ROLLBACK');
      return erro(res, 'Prêmio não encontrado', 404);
    }

    const premio = resPremio.rows[0];
    const resCliente = await client.query(
      'SELECT ios_coins FROM clientes WHERE id = $1', [clienteId]
    );
    const saldo = parseFloat(resCliente.rows[0].ios_coins);

    if (saldo < parseFloat(premio.custo_coins)) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Você tem ${saldo.toFixed(0)} coins, precisa de ${premio.custo_coins}`);
    }

    await client.query(
      'UPDATE clientes SET ios_coins = ios_coins - $1 WHERE id = $2',
      [premio.custo_coins, clienteId]
    );

    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'resgate',$4)`,
      [uuidv4(), clienteId, -parseFloat(premio.custo_coins), `Resgate: ${premio.nome}`]
    );

    await client.query('COMMIT');
    return ok(res, { novoSaldo: saldo - parseFloat(premio.custo_coins) }, `Prêmio "${premio.nome}" resgatado!`);

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao resgatar prêmio', 500);
  } finally {
    client.release();
  }
}

module.exports = { creditarCompra, resgatar };
