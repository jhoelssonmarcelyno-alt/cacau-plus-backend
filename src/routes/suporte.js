const express = require('express');
const router  = express.Router();
const { autenticar } = require('../middlewares/auth');
const { abrirTicket } = require('../controllers/operacionalController');

router.post('/', autenticar, abrirTicket);
module.exports = router;
