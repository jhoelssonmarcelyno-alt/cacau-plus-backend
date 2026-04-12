// src/controllers/authController.js
// Cadastro e login de clientes e lojas

const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const pool = require('../config/db');
const { gerarToken } = require('../config/jwt');
const { criado, ok, erro } = require('../utils/resposta');

const COINS_BOAS_VINDAS = 100;
const COINS_INDICACAO   = 50;

// ── Helpers ───────────────────────────────────────────────────
function gerarCodigoIndicacao(telefone) {
  const digits = telefone.replace(/\D/g, '');
  const suffix = digits.slice(-4).padStart(4, '0');
  return `CAC${suffix}${Date.now().toString().slice(-3)}`;
}

// ── POST /auth/cadastro-cliente ───────────────────────────────
async function cadastrarCliente(req, res) {
  const { nome, telefone, email, senha, codigoIndicacao } = req.body;

  if (!nome || !telefone || !email || !senha) {
    return erro(res, 'Campos obrigatórios: nome, telefone, email, senha');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Verifica e-mail duplicado
    const existe = await client.query(
      'SELECT id FROM clientes WHERE email = $1', [email.toLowerCase()]
    );
    if (existe.rows.length > 0) {
      await client.query('ROLLBACK');
      return erro(res, 'E-mail já cadastrado');
    }

    const hash   = await bcrypt.hash(senha, 10);
    const id     = uuidv4();
    const codigo = gerarCodigoIndicacao(telefone);

    await client.query(
      `INSERT INTO clientes (id, nome, telefone, email, senha_hash, ios_coins, codigo_indicacao, indicado_por)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [id, nome, telefone, email.toLowerCase(), hash, COINS_BOAS_VINDAS, codigo,
       codigoIndicacao || null]
    );

    // Registra transação de boas-vindas
    await client.query(
      `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
       VALUES ($1,$2,$3,'boas_vindas','Boas-vindas ao Cacau Plus!')`,
      [uuidv4(), id, COINS_BOAS_VINDAS]
    );

    // Credita coins de indicação para quem indicou
    if (codigoIndicacao) {
      const indicador = await client.query(
        'SELECT id FROM clientes WHERE codigo_indicacao = $1', [codigoIndicacao]
      );
      if (indicador.rows.length > 0) {
        const indId = indicador.rows[0].id;
        await client.query(
          'UPDATE clientes SET ios_coins = ios_coins + $1 WHERE id = $2',
          [COINS_INDICACAO, indId]
        );
        await client.query(
          `INSERT INTO transacoes (id, cliente_id, coins, tipo, descricao)
           VALUES ($1,$2,$3,'indicacao','Amigo indicado se cadastrou!')`,
          [uuidv4(), indId, COINS_INDICACAO]
        );
      }
    }

    await client.query('COMMIT');

    const token = gerarToken({ id, tipo: 'cliente', nome, email });
    return criado(res, { token, id, nome, email, iosCoins: COINS_BOAS_VINDAS, codigoIndicacao: codigo },
      'Cliente cadastrado com sucesso!');

  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao cadastrar cliente', 500);
  } finally {
    client.release();
  }
}

// ── POST /auth/cadastro-loja ──────────────────────────────────
async function cadastrarLoja(req, res) {
  const { nome, cpfOuCnpj, endereco, telefone, email, senha, coinsPorReal, categoria } = req.body;

  if (!nome || !cpfOuCnpj || !endereco || !telefone || !email || !senha || !coinsPorReal) {
    return erro(res, 'Preencha todos os campos obrigatórios');
  }

  try {
    const existe = await pool.query(
      'SELECT id FROM lojas WHERE email = $1', [email.toLowerCase()]
    );
    if (existe.rows.length > 0) return erro(res, 'E-mail já cadastrado');

    const hash = await bcrypt.hash(senha, 10);
    const id   = uuidv4();

    await pool.query(
      `INSERT INTO lojas (id, nome, cpf_cnpj, endereco, telefone, email, senha_hash, coins_por_real, categoria)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [id, nome, cpfOuCnpj, endereco, telefone, email.toLowerCase(), hash,
       parseFloat(coinsPorReal), categoria || null]
    );

    const token = gerarToken({ id, tipo: 'loja', nome, email });
    return criado(res, { token, id, nome, email, coinsPorReal: parseFloat(coinsPorReal) },
      'Loja cadastrada com sucesso!');

  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao cadastrar loja', 500);
  }
}

// ── POST /auth/login ──────────────────────────────────────────
async function login(req, res) {
  const { email, senha } = req.body;
  if (!email || !senha) return erro(res, 'E-mail e senha obrigatórios');

  const emailNorm = email.toLowerCase();

  try {
    // Tenta cliente
    const resCliente = await pool.query(
      'SELECT * FROM clientes WHERE email = $1', [emailNorm]
    );
    if (resCliente.rows.length > 0) {
      const c = resCliente.rows[0];
      const ok_ = await bcrypt.compare(senha, c.senha_hash);
      if (!ok_) return erro(res, 'Senha incorreta', 401);

      const token = gerarToken({ id: c.id, tipo: 'cliente', nome: c.nome, email: c.email });
      return ok(res, {
        token, tipo: 'cliente',
        id: c.id, nome: c.nome, email: c.email,
        iosCoins: parseFloat(c.ios_coins),
        codigoIndicacao: c.codigo_indicacao,
      });
    }

    // Tenta loja
    const resLoja = await pool.query(
      'SELECT * FROM lojas WHERE email = $1', [emailNorm]
    );
    if (resLoja.rows.length > 0) {
      const l = resLoja.rows[0];
      const ok_ = await bcrypt.compare(senha, l.senha_hash);
      if (!ok_) return erro(res, 'Senha incorreta', 401);

      const token = gerarToken({ id: l.id, tipo: 'loja', nome: l.nome, email: l.email });
      return ok(res, {
        token, tipo: 'loja',
        id: l.id, nome: l.nome, email: l.email,
        coinsPorReal: parseFloat(l.coins_por_real),
        endereco: l.endereco,
      });
    }

    return erro(res, 'Nenhuma conta encontrada com esse e-mail', 404);

  } catch (e) {
    console.error(e);
    return erro(res, 'Erro ao fazer login', 500);
  }
}

module.exports = { cadastrarCliente, cadastrarLoja, login };
