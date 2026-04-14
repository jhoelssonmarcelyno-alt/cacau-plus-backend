const express = require('express');
const router  = express.Router();
const { listarBanners } = require('../controllers/bannersController');

router.get('/', listarBanners);
module.exports = router;
