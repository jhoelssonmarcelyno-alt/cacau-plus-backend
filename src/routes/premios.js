const express = require('express');
const router  = express.Router();
const { autenticar, apenasLoja } = require('../middlewares/auth');
const { listar, criar } = require('../controllers/premioController');

router.get('/',  listar);
router.post('/', autenticar, apenasLoja, criar);

module.exports = router;
