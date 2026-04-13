const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const {
  criarAvaliacao,
  listarAvaliacoesDaLoja,
  minhasAvaliacoes,
  deletarAvaliacao,
} = require('../controllers/avaliacaoController');

router.get('/loja/:lojaId', listarAvaliacoesDaLoja);
router.post('/',            autenticar, apenasCliente, criarAvaliacao);
router.get('/minhas',       autenticar, apenasCliente, minhasAvaliacoes);
router.delete('/:id',       autenticar, apenasCliente, deletarAvaliacao);

module.exports = router;
