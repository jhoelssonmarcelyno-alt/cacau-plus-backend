const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente, apenasLoja } = require('../middlewares/auth');
const {
  progressoCliente, clientesDaLoja, brindesDaLoja,
  configurarFidelidade, transacoesDaLoja,
} = require('../controllers/fidelidadeController');

router.get('/progresso/:lojaId', autenticar, apenasCliente, progressoCliente);
router.get('/clientes',          autenticar, apenasLoja,    clientesDaLoja);
router.get('/brindes',           autenticar, apenasLoja,    brindesDaLoja);
router.get('/transacoes',        autenticar, apenasLoja,    transacoesDaLoja);
router.patch('/configurar',      autenticar, apenasLoja,    configurarFidelidade);

module.exports = router;
