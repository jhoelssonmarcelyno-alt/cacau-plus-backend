const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja, apenasCliente } = require('../middlewares/auth');
const { creditarCompra, resgatar } = require('../controllers/coinsController');

router.post('/creditar-compra', autenticar, apenasLoja,    creditarCompra);
router.post('/resgatar',        autenticar, apenasCliente, resgatar);

module.exports = router;
