const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { listarTarefas, concluirTarefa } = require('../controllers/tarefasController');

router.get('/',              autenticar, apenasCliente, listarTarefas);
router.post('/:id/concluir', autenticar, apenasCliente, concluirTarefa);

module.exports = router;
