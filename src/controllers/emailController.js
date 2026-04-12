// src/controllers/emailController.js
// Recuperação de senha via e-mail com Nodemailer

const crypto = require('crypto');
const pool   = require('../config/db');
const { erro, ok } = require('../utils/resposta');

let transporter;

async function getTransporter() {
  if (transporter) return transporter;
  const nodemailer = require('nodemailer');
  transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: process.env.EMAIL_USER,
      pass: process.env.EMAIL_PASS,
    },
  });
  return transporter;
}

// POST /auth/recuperar-senha
async function recuperarSenha(req, res) {
  const { email } = req.body;
  if (!email) return erro(res, 'Informe o e-mail');

  const emailNorm = email.trim().toLowerCase();

  try {
    // Verifica se existe no banco (cliente ou loja)
    const resCliente = await pool.query(
      'SELECT id, nome FROM clientes WHERE email = $1', [emailNorm]
    );
    const resLoja = await pool.query(
      'SELECT id, nome FROM lojas WHERE email = $1', [emailNorm]
    );

    const conta = resCliente.rows[0] || resLoja.rows[0];
    const tipo  = resCliente.rows[0] ? 'cliente' : 'loja';

    // Sempre retorna sucesso por segurança (não revela se e-mail existe)
    if (!conta) return ok(res, null, 'Se o e-mail estiver cadastrado, você receberá as instruções.');

    // Gera token seguro válido por 1 hora
    const token   = crypto.randomBytes(32).toString('hex');
    const expiraEm = new Date(Date.now() + 60 * 60 * 1000); // 1 hora

    // Salva token no banco
    await pool.query(
      `INSERT INTO tokens_recuperacao (token, conta_id, tipo, expira_em)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (conta_id) DO UPDATE SET token = $1, expira_em = $4`,
      [token, conta.id, tipo, expiraEm]
    );

    // Monta link de redefinição
    const link = `${process.env.APP_URL || 'https://cacau-plus-backend.onrender.com'}/auth/redefinir-senha/${token}`;

    // Envia e-mail
    const mail = await getTransporter();
    await mail.sendMail({
      from: `"Cacau Plus" <${process.env.EMAIL_USER}>`,
      to: emailNorm,
      subject: '🍫 Redefinição de senha — Cacau Plus',
      html: `
        <div style="font-family:Arial,sans-serif;max-width:500px;margin:0 auto;">
          <div style="background:#3E2723;padding:24px;text-align:center;border-radius:12px 12px 0 0;">
            <h1 style="color:#D4AF37;margin:0;">🍫 Cacau Plus</h1>
            <p style="color:#fff;margin:8px 0 0;">Ilhéus, BA</p>
          </div>
          <div style="background:#fff;padding:32px;border:1px solid #eee;border-radius:0 0 12px 12px;">
            <h2 style="color:#3E2723;">Olá, ${conta.nome}!</h2>
            <p style="color:#555;">Recebemos uma solicitação para redefinir a senha da sua conta no <strong>Cacau Plus</strong>.</p>
            <p style="color:#555;">Clique no botão abaixo para criar uma nova senha:</p>
            <div style="text-align:center;margin:32px 0;">
              <a href="${link}"
                 style="background:#3E2723;color:#D4AF37;padding:14px 32px;border-radius:8px;text-decoration:none;font-weight:bold;font-size:16px;">
                Redefinir senha
              </a>
            </div>
            <p style="color:#999;font-size:13px;">Este link expira em <strong>1 hora</strong>.</p>
            <p style="color:#999;font-size:13px;">Se você não solicitou a redefinição, ignore este e-mail.</p>
            <hr style="border:none;border-top:1px solid #eee;margin:24px 0;">
            <p style="color:#ccc;font-size:12px;text-align:center;">Cacau Plus — Plataforma de fidelidade de Ilhéus, BA</p>
          </div>
        </div>
      `,
    });

    return ok(res, null, 'Se o e-mail estiver cadastrado, você receberá as instruções.');
  } catch (e) {
    console.error('Erro ao enviar e-mail:', e);
    return erro(res, 'Erro ao processar solicitação', 500);
  }
}

// GET /auth/redefinir-senha/:token
// Página HTML para o usuário digitar a nova senha
async function paginaRedefinir(req, res) {
  const { token } = req.params;
  res.send(`
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Redefinir senha — Cacau Plus</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: Arial, sans-serif; background: #f5f5f5; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
        .card { background: #fff; border-radius: 16px; padding: 40px 32px; max-width: 420px; width: 90%; box-shadow: 0 4px 20px rgba(0,0,0,0.1); }
        .logo { text-align: center; margin-bottom: 24px; }
        .logo h1 { color: #3E2723; font-size: 28px; }
        .logo p { color: #999; font-size: 14px; }
        label { display: block; margin-bottom: 6px; color: #555; font-size: 14px; }
        input { width: 100%; padding: 12px 16px; border: 1px solid #ddd; border-radius: 8px; font-size: 16px; margin-bottom: 16px; outline: none; }
        input:focus { border-color: #3E2723; }
        button { width: 100%; padding: 14px; background: #3E2723; color: #D4AF37; border: none; border-radius: 8px; font-size: 16px; font-weight: bold; cursor: pointer; }
        button:hover { background: #6D4C41; }
        .msg { text-align: center; margin-top: 16px; font-size: 15px; }
        .sucesso { color: #388E3C; }
        .erro { color: #D32F2F; }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="logo">
          <h1>🍫 Cacau Plus</h1>
          <p>Redefinir senha</p>
        </div>
        <form id="form">
          <label>Nova senha</label>
          <input type="password" id="senha" placeholder="Mínimo 6 caracteres" minlength="6" required>
          <label>Confirmar nova senha</label>
          <input type="password" id="confirmar" placeholder="Repita a senha" required>
          <button type="submit">Salvar nova senha</button>
        </form>
        <div class="msg" id="msg"></div>
      </div>
      <script>
        document.getElementById('form').addEventListener('submit', async (e) => {
          e.preventDefault();
          const senha = document.getElementById('senha').value;
          const confirmar = document.getElementById('confirmar').value;
          const msg = document.getElementById('msg');
          if (senha !== confirmar) {
            msg.className = 'msg erro';
            msg.textContent = 'As senhas não coincidem.';
            return;
          }
          try {
            const res = await fetch('/auth/redefinir-senha/${token}', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ senha })
            });
            const data = await res.json();
            if (data.sucesso) {
              msg.className = 'msg sucesso';
              msg.textContent = '✅ Senha redefinida com sucesso! Você já pode fazer login no app.';
              document.getElementById('form').style.display = 'none';
            } else {
              msg.className = 'msg erro';
              msg.textContent = data.mensagem || 'Erro ao redefinir senha.';
            }
          } catch {
            msg.className = 'msg erro';
            msg.textContent = 'Erro de conexão. Tente novamente.';
          }
        });
      </script>
    </body>
    </html>
  `);
}

// POST /auth/redefinir-senha/:token
async function redefinirSenha(req, res) {
  const { token } = req.params;
  const { senha  } = req.body;

  if (!senha || senha.length < 6) return erro(res, 'Senha deve ter no mínimo 6 caracteres');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Busca token válido
    const resTk = await client.query(
      `SELECT * FROM tokens_recuperacao
       WHERE token = $1 AND expira_em > NOW()`,
      [token]
    );

    if (resTk.rows.length === 0) {
      await client.query('ROLLBACK');
      return erro(res, 'Link inválido ou expirado. Solicite um novo.', 400);
    }

    const { conta_id, tipo } = resTk.rows[0];
    const bcrypt = require('bcryptjs');
    const hash   = await bcrypt.hash(senha, 10);

    // Atualiza senha na tabela correta
    const tabela = tipo === 'cliente' ? 'clientes' : 'lojas';
    await client.query(
      `UPDATE ${tabela} SET senha_hash = $1 WHERE id = $2`,
      [hash, conta_id]
    );

    // Remove token usado
    await client.query(
      'DELETE FROM tokens_recuperacao WHERE token = $1', [token]
    );

    await client.query('COMMIT');
    return ok(res, null, 'Senha redefinida com sucesso!');
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    return erro(res, 'Erro ao redefinir senha', 500);
  } finally {
    client.release();
  }
}

module.exports = { recuperarSenha, paginaRedefinir, redefinirSenha };