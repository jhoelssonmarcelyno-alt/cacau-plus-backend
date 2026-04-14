const express = require('express');
const router  = express.Router();
const { autenticar, apenasCliente } = require('../middlewares/auth');
const { registrarToken } = require('../controllers/pushController');

router.post('/registrar', autenticar, apenasCliente, registrarToken);
module.exports = router;
