const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { minhasNotificacoes, lerTodas } = require('../controllers/notificacoesController');

router.use(autenticar, apenasCliente);
router.get('/',          minhasNotificacoes);
router.patch('/lerTodas', lerTodas);
module.exports = router;
