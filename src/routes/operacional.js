const express = require('express');
const router  = express.Router();
const { autenticar, apenasAdmin } = require('../middlewares/auth');
const {
  listarLogs, clientesInativos,
  exportarClientesCSV, exportarLojasCSV, exportarTransacoesCSV,
  listarTickets, responderTicket,
} = require('../controllers/operacionalController');

router.use(autenticar, apenasAdmin);
router.get('/logs',                      listarLogs);
router.get('/clientes-inativos',         clientesInativos);
router.get('/exportar/clientes',         exportarClientesCSV);
router.get('/exportar/lojas',            exportarLojasCSV);
router.get('/exportar/transacoes',       exportarTransacoesCSV);
router.get('/tickets',                   listarTickets);
router.patch('/tickets/:id/responder',   responderTicket);

module.exports = router;
