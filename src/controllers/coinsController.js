const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');
const { registrarVisita, verificarBrinde } = require('./fidelidadeController');
const { calcularMultiplicador, atualizarNivel } = require('./niveisController');

const COINS_POR_PCT = 100;
const MINIMO_COINS  = 500;

async function processarCompra(req, res) {
  const lojaId = req.usuario.id;
  const { clienteId, valorCompra, coinsParaDescontar } = req.body;
  if (!clienteId || !valorCompra || valorCompra <= 0)
    return erro(res, 'clienteId e valorCompra são obrigatórios');

  const coinsDesc = coinsParaDescontar || 0;
  if (coinsDesc > 0 && coinsDesc < MINIMO_COINS)
    return erro(res, `Mínimo de ${MINIMO_COINS} coins para desconto`);
  if (coinsDesc % COINS_POR_PCT !== 0)
    return erro(res, 'Coins deve ser múltiplo de 100');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const resLoja = await client.query(
      'SELECT nome, coins_por_real, desconto_max_pct FROM lojas WHERE id=$1', [lojaId]
    );
    if (!resLoja.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Loja não encontrada', 404); }
    const loja = resLoja.rows[0];
    const maxCoinsDesc = parseFloat(loja.desconto_max_pct) * COINS_POR_PCT;

    if (coinsDesc > maxCoinsDesc) {
      await client.query('ROLLBACK');
      return erro(res, `Loja aceita no máximo ${maxCoinsDesc} coins de desconto`);
    }

    const resCliente = await client.query(
      'SELECT nome, ios_coins, nivel, total_coins_ganhos FROM clientes WHERE id=$1', [clienteId]
    );
    if (!resCliente.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Cliente não encontrado', 404); }
    const saldoAtual  = parseFloat(resCliente.rows[0].ios_coins);
    const nomeCliente = resCliente.rows[0].nome;
    const nivel       = resCliente.rows[0].nivel || 'bronze';

    if (coinsDesc > saldoAtual) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Cliente tem ${saldoAtual.toFixed(0)} coins.`);
    }

    const descontoPct   = coinsDesc / COINS_POR_PCT;
    const descontoReais = (valorCompra * descontoPct) / 100;
    const valorFinal    = valorCompra - descontoReais;
    const coinsPorReal  = parseFloat(loja.coins_por_real);

    // Verifica campanha ativa
    const resCampanha = await client.query(
      `SELECT multiplicador, titulo FROM campanhas
       WHERE ativo=true AND inicio <= NOW() AND fim >= NOW()
       ORDER BY multiplicador DESC LIMIT 1`
    );
    const campanha = resCampanha.rows[0];
    const multCampanha = campanha ? parseFloat(campanha.multiplicador) : 1;

    // Multiplicador de nível
    const multNivel = calcularMultiplicador(nivel);

    // Multiplicador final = maior entre nível e campanha
    const multiplicadorFinal = Math.max(multNivel, multCampanha);
    const coinsGanhos = valorFinal * coinsPorReal * multiplicadorFinal;
    const saldoFinal  = saldoAtual - coinsDesc + coinsGanhos;

    await client.query('UPDATE clientes SET ios_coins=$1, total_coins_ganhos = total_coins_ganhos + $2 WHERE id=$3',
      [saldoFinal, coinsGanhos, clienteId]);

    if (coinsDesc > 0) {
      await client.query(
        `INSERT INTO transacoes (id,cliente_id,coins,tipo,loja_id,descricao) VALUES ($1,$2,$3,'resgate',$4,$5)`,
        [uuidv4(), clienteId, -coinsDesc, lojaId, `Desconto ${descontoPct}% em ${loja.nome}`]
      );
    }
    await client.query(
      `INSERT INTO transacoes (id,cliente_id,coins,tipo,loja_id,descricao) VALUES ($1,$2,$3,'compra',$4,$5)`,
      [uuidv4(), clienteId, coinsGanhos, lojaId,
       `Compra em ${loja.nome} — R$ ${valorFinal.toFixed(2)}${multiplicadorFinal > 1 ? ` (${multiplicadorFinal}x)` : ''}`]
    );

    await registrarVisita(clienteId, lojaId, client);
    const brinde = await verificarBrinde(clienteId, lojaId, client);
    const novoNivel = await atualizarNivel(clienteId, client);

    await client.query('COMMIT');

    return ok(res, {
      nomeCliente,
      valorCompra:        parseFloat(valorCompra.toFixed(2)),
      descontoPct,
      descontoReais:      parseFloat(descontoReais.toFixed(2)),
      valorFinal:         parseFloat(valorFinal.toFixed(2)),
      coinsDebitados:     coinsDesc,
      coinsGanhos:        parseFloat(coinsGanhos.toFixed(2)),
      multiplicador:      multiplicadorFinal,
      campanhaAtiva:      campanha?.titulo || null,
      saldoAnterior:      parseFloat(saldoAtual.toFixed(2)),
      saldoFinal:         parseFloat(saldoFinal.toFixed(2)),
      nivel:              novoNivel,
      brinde,
    }, 'Compra processada!');

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao processar compra', 500);
  } finally {
    client.release();
  }
}

async function buscarSaldoCliente(req, res) {
  const { clienteId } = req.params;
  try {
    const result = await pool.query(
      'SELECT nome, ios_coins, nivel FROM clientes WHERE id=$1', [clienteId]
    );
    if (!result.rows.length) return erro(res, 'Cliente não encontrado', 404);
    return ok(res, {
      nome:     result.rows[0].nome,
      iosCoins: parseFloat(result.rows[0].ios_coins),
      nivel:    result.rows[0].nivel,
    });
  } catch (e) { return erro(res, 'Erro ao buscar saldo', 500); }
}

async function resgatar(req, res) {
  const { premioId } = req.body;
  const clienteId = req.usuario.id;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const resPremio = await client.query('SELECT * FROM premios WHERE id=$1', [premioId]);
    if (!resPremio.rows.length) { await client.query('ROLLBACK'); return erro(res, 'Prêmio não encontrado', 404); }
    const premio = resPremio.rows[0];
    const resC = await client.query('SELECT ios_coins FROM clientes WHERE id=$1', [clienteId]);
    const saldo = parseFloat(resC.rows[0].ios_coins);
    if (saldo < parseFloat(premio.custo_coins)) {
      await client.query('ROLLBACK');
      return erro(res, `Saldo insuficiente. Você tem ${saldo.toFixed(0)} coins.`);
    }
    await client.query('UPDATE clientes SET ios_coins = ios_coins - $1 WHERE id=$2', [premio.custo_coins, clienteId]);
    await client.query(
      `INSERT INTO transacoes (id,cliente_id,coins,tipo,descricao) VALUES ($1,$2,$3,'resgate',$4)`,
      [uuidv4(), clienteId, -parseFloat(premio.custo_coins), `Resgate: ${premio.nome}`]
    );
    await client.query('COMMIT');
    return ok(res, { novoSaldo: saldo - parseFloat(premio.custo_coins) }, `Prêmio resgatado!`);
  } catch (e) {
    await client.query('ROLLBACK');
    return erro(res, 'Erro ao resgatar', 500);
  } finally {
    client.release();
  }
}

module.exports = { processarCompra, buscarSaldoCliente, resgatar };
