const express = require('express');
const router  = express.Router();
const { autenticar } = require('../middlewares/auth');
const { campanhaAtiva } = require('../controllers/campanhasController');

router.get('/ativa', autenticar, campanhaAtiva);
module.exports = router;
