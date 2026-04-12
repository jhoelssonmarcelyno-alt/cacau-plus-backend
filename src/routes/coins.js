const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja, apenasCliente } = require('../middlewares/auth');
const { processarCompra, buscarSaldoCliente, resgatar } = require('../controllers/coinsController');

router.post('/compra',          autenticar, apenasLoja,    processarCompra);
router.get('/saldo/:clienteId', autenticar, apenasLoja,    buscarSaldoCliente);
router.post('/resgatar',        autenticar, apenasCliente, resgatar);

module.exports = router;
