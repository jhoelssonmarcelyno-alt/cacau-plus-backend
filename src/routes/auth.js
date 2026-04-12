const express = require('express');
const router  = express.Router();
const { cadastrarCliente, cadastrarLoja, login } = require('../controllers/authController');

router.post('/cadastro-cliente', cadastrarCliente);
router.post('/cadastro-loja',    cadastrarLoja);
router.post('/login',            login);

module.exports = router;
