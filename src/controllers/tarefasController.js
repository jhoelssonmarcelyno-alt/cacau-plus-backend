const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// GET /tarefas — lista todas as tarefas com status do cliente
async function listarTarefas(req, res) {
  const clienteId = req.usuario.id;
  try {
    const result = await pool.query(
      `SELECT t.id, t.titulo, t.descricao, t.coins, t.tipo, t.link,
              CASE WHEN tc.id IS NOT NULL THEN true ELSE false END AS concluida
       FROM tarefas t
       LEFT JOIN tarefas_concluidas tc
         ON tc.tarefa_id = t.id AND tc.cliente_id = $1
       WHERE t.ativo = true
       ORDER BY concluida ASC, t.coins DESC`,
      [clienteId]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar tarefas', 500);
  }
}

// POST /tarefas/:id/concluir — cliente conclui uma tarefa
async function concluirTarefa(req, res) {
  const clienteId = req.usuario.id;
  const { id: tarefaId } = req.params;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Busca tarefa
    const resTarefa = await client.query(
      'SELECT * FROM tarefas WHERE id=$1 AND ativo=true', [tarefaId]
    );
    if (!resTarefa.rows.length) {
      await client.query('ROLLBACK');
      return erro(res, 'Tarefa não encontrada', 404);
    }
    const tarefa = resTarefa.rows[0];

    // Verifica se já concluiu
    const jaFez = await client.query(
      'SELECT id FROM tarefas_concluidas WHERE cliente_id=$1 AND tarefa_id=$2',
      [clienteId, tarefaId]
    );
    if (jaFez.rows.length) {
      await client.query('ROLLBACK');
      return erro(res, 'Você já completou esta tarefa!');
    }

    // Registra conclusão
    await client.query(
      'INSERT INTO tarefas_concluidas (id, cliente_id, tarefa_id) VALUES ($1,$2,$3)',
      [uuidv4(), clienteId, tarefaId]
    );

    // Credita coins
    await client.query(
      'UPDATE clientes SET ios_coins = ios_coins + $1 WHERE id = $2',
      [tarefa.coins, clienteId]
    );

    // Registra transação
    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'boas_vindas',$4)`,
      [uuidv4(), clienteId, tarefa.coins, `Tarefa concluída: ${tarefa.titulo}`]
    );

    await client.query('COMMIT');

    return ok(res, {
      coinsGanhos: parseFloat(tarefa.coins),
      tarefa: tarefa.titulo,
    }, `+${tarefa.coins} coins! Tarefa concluída!`);

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao concluir tarefa', 500);
  } finally {
    client.release();
  }
}

module.exports = { listarTarefas, concluirTarefa };
