const express = require('express');
const router  = express.Router();
const { autenticar, apenasAdmin } = require('../middlewares/auth');
const {
  saldoAdmin, gerarCoins, enviarCoins,
  realizarSorteio, historicoSorteios, historicoAdmin,
} = require('../controllers/adminCoinsController');

router.use(autenticar, apenasAdmin);

router.get('/coins/saldo',         saldoAdmin);
router.post('/coins/gerar',        gerarCoins);
router.post('/coins/enviar',       enviarCoins);
router.get('/coins/historico',     historicoAdmin);
router.post('/sorteio/realizar',   realizarSorteio);
router.get('/sorteio/historico',   historicoSorteios);

module.exports = router;
