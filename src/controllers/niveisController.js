const pool = require('../config/db');

// Regras de nível
const NIVEIS = [
  { nome: 'bronze',   minCoins: 0,    cor: '#CD7F32', emoji: '🥉', beneficio: '1x coins padrão' },
  { nome: 'prata',    minCoins: 500,  cor: '#C0C0C0', emoji: '🥈', beneficio: '1.2x coins em compras' },
  { nome: 'ouro',     minCoins: 2000, cor: '#FFD700', emoji: '🥇', beneficio: '1.5x coins em compras' },
  { nome: 'diamante', minCoins: 5000, cor: '#B9F2FF', emoji: '💎', beneficio: '2x coins em compras' },
];

function calcularNivel(totalCoins) {
  for (let i = NIVEIS.length - 1; i >= 0; i--) {
    if (totalCoins >= NIVEIS[i].minCoins) return NIVEIS[i];
  }
  return NIVEIS[0];
}

function calcularMultiplicador(nivelNome) {
  switch (nivelNome) {
    case 'prata':    return 1.2;
    case 'ouro':     return 1.5;
    case 'diamante': return 2.0;
    default:         return 1.0;
  }
}

async function atualizarNivel(clienteId, client) {
  const res = await client.query(
    'SELECT nivel, total_coins_ganhos FROM clientes WHERE id=$1', [clienteId]
  );
  if (!res.rows.length) return;

  const totalCoins = parseFloat(res.rows[0].total_coins_ganhos);
  const nivelAtual = res.rows[0].nivel;
  const novoNivel  = calcularNivel(totalCoins).nome;

  if (novoNivel !== nivelAtual) {
    await client.query(
      'UPDATE clientes SET nivel=$1 WHERE id=$2', [novoNivel, clienteId]
    );

    // Notifica o cliente sobre mudança de nível
    const info = NIVEIS.find(n => n.nome === novoNivel);
    const { v4: uuidv4 } = require('uuid');
    await client.query(
      `INSERT INTO notificacoes (id, cliente_id, titulo, mensagem, tipo)
       VALUES ($1,$2,$3,$4,'nivel')`,
      [uuidv4(), clienteId,
       `${info.emoji} Você subiu para ${novoNivel.toUpperCase()}!`,
       `Parabéns! Agora você é ${novoNivel} e tem ${info.beneficio}!`]
    );

    return novoNivel;
  }
  return nivelAtual;
}

module.exports = { NIVEIS, calcularNivel, calcularMultiplicador, atualizarNivel };
