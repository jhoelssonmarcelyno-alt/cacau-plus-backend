const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja } = require('../middlewares/auth');
const { perfil, atualizarCoinsPorReal, listarLojas } = require('../controllers/lojaController');

// Público
router.get('/', listarLojas);

// Autenticado (loja)
router.use(autenticar, apenasLoja);
router.get('/perfil',          perfil);
router.patch('/coins-por-real', atualizarCoinsPorReal);

module.exports = router;
