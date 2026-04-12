const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja } = require('../middlewares/auth');
const { perfil, atualizarCoinsPorReal, listarLojas, configurarLoja } = require('../controllers/lojaController');

router.get('/', listarLojas);
router.use(autenticar, apenasLoja);
router.get('/perfil',          perfil);
router.patch('/coins-por-real', atualizarCoinsPorReal);
router.patch('/configurar',    configurarLoja);

module.exports = router;
