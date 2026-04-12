const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { perfil, extrato } = require('../controllers/clienteController');

router.use(autenticar, apenasCliente);
router.get('/perfil',  perfil);
router.get('/extrato', extrato);

module.exports = router;
