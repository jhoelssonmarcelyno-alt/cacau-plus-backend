const express = require('express');
const router  = express.Router();
const { autenticar, apenasAdmin } = require('../middlewares/auth');
const {
  loginAdmin, dashboard,
  listarLojas, alterarStatusLoja,
  listarClientes, alterarStatusCliente,
  listarTarefas, criarTarefa, editarTarefa,
  listarPremios, criarPremio, deletarPremio,
  relatorio,
} = require('../controllers/adminController');
const { listarCampanhas, criarCampanha, editarCampanha } = require('../controllers/campanhasController');
const { enviarNotificacao } = require('../controllers/notificacoesController');

router.post('/login', loginAdmin);
router.use(autenticar, apenasAdmin);

router.get('/dashboard',              dashboard);
router.get('/lojas',                  listarLojas);
router.patch('/lojas/:id/status',     alterarStatusLoja);
router.get('/clientes',               listarClientes);
router.patch('/clientes/:id/status',  alterarStatusCliente);
router.get('/tarefas',                listarTarefas);
router.post('/tarefas',               criarTarefa);
router.patch('/tarefas/:id',          editarTarefa);
router.get('/premios',                listarPremios);
router.post('/premios',               criarPremio);
router.delete('/premios/:id',         deletarPremio);
router.get('/relatorio',              relatorio);
router.get('/campanhas',              listarCampanhas);
router.post('/campanhas',             criarCampanha);
router.patch('/campanhas/:id',        editarCampanha);
router.post('/notificacoes',          enviarNotificacao);

module.exports = router;
