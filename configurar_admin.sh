#!/bin/bash
# Execute dentro de: /f/CACAU PLUS/Cacau_Plus/mobile/backend
# bash configurar_admin.sh

echo "🍫 Configurando rota admin..."

# ── Atualizar clienteController.js ───────────────────────────
cat > src/controllers/clienteController.js << 'CTRL'
// src/controllers/clienteController.js

const pool = require('../config/db');
const { ok, erro } = require('../utils/resposta');

// GET /cliente/perfil
async function perfil(req, res) {
  try {
    const result = await pool.query(
      'SELECT id, nome, telefone, email, ios_coins, codigo_indicacao FROM clientes WHERE id = $1',
      [req.usuario.id]
    );
    if (result.rows.length === 0) return erro(res, 'Cliente não encontrado', 404);
    return ok(res, result.rows[0]);
  } catch (e) {
    return erro(res, 'Erro ao buscar perfil', 500);
  }
}

// GET /cliente/extrato
async function extrato(req, res) {
  try {
    const result = await pool.query(
      `SELECT id, coins, tipo, descricao, loja_id, criado_em
       FROM transacoes WHERE cliente_id = $1
       ORDER BY criado_em DESC LIMIT 50`,
      [req.usuario.id]
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao buscar extrato', 500);
  }
}

// GET /cliente/todos — usado pelo painel admin
async function listarTodosClientes(req, res) {
  try {
    const result = await pool.query(
      `SELECT id, nome, telefone, email, ios_coins, codigo_indicacao, criado_em
       FROM clientes ORDER BY criado_em DESC`
    );
    return ok(res, result.rows);
  } catch (e) {
    return erro(res, 'Erro ao listar clientes', 500);
  }
}

module.exports = { perfil, extrato, listarTodosClientes };
CTRL

# ── Atualizar routes/cliente.js ──────────────────────────────
cat > src/routes/cliente.js << 'ROUTE'
const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { perfil, extrato, listarTodosClientes } = require('../controllers/clienteController');

// Rota admin — sem middleware (URL conhecida só pelo admin)
router.get('/todos', listarTodosClientes);

// Rotas autenticadas
router.use(autenticar, apenasCliente);
router.get('/perfil',  perfil);
router.get('/extrato', extrato);

module.exports = router;
ROUTE

echo "✅ Backend atualizado!"

# ── Commit e push ─────────────────────────────────────────────
git add .
git commit -m "feat: rota admin listar todos clientes"
git push

echo ""
echo "✅ Push feito! Aguarde o Render fazer o deploy."
echo ""
echo "Agora atualize o admin_screen.dart:"
echo "Troque: /admin/clientes"
echo "Por:    /cliente/todos"
