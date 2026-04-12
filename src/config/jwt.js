// src/config/jwt.js
// Geração e verificação de tokens JWT

const jwt = require('jsonwebtoken');
require('dotenv').config();

const SECRET = process.env.JWT_SECRET || 'cacau_plus_dev_secret';

function gerarToken(payload) {
  return jwt.sign(payload, SECRET, { expiresIn: '30d' });
}

function verificarToken(token) {
  return jwt.verify(token, SECRET);
}

module.exports = { gerarToken, verificarToken };
