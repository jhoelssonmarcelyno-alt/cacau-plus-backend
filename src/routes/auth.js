// src/routes/auth.js — atualizado com recuperação de senha

const express = require('express');
const router  = express.Router();
const { cadastrarCliente, cadastrarLoja, login } = require('../controllers/authController');
const { recuperarSenha, paginaRedefinir, redefinirSenha } = require('../controllers/emailController');

router.post('/cadastro-cliente',     cadastrarCliente);
router.post('/cadastro-loja',        cadastrarLoja);
router.post('/login',                login);
router.post('/recuperar-senha',      recuperarSenha);
router.get('/redefinir-senha/:token',  paginaRedefinir);
router.post('/redefinir-senha/:token', redefinirSenha);

module.exports = router;