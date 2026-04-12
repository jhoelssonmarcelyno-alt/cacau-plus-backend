const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { perfil, extrato, listarTodosClientes } = require('../controllers/clienteController');

// Rota admin — sem middleware (URL conhecida só pelo admin)
router.get('/todos', listarTodosClientes);

// Rotas autenticadas
router.use(autenticar, apenasCliente);
router.get('/perfil',  perfil);
router.get('/extrato', extrato);

module.exports = router;
