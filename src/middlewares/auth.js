const { verificarToken } = require('../config/jwt');
const { naoAutorizado } = require('../utils/resposta');

function autenticar(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) return naoAutorizado(res);
  const token = authHeader.split(' ')[1];
  try {
    req.usuario = verificarToken(token);
    next();
  } catch {
    return naoAutorizado(res, 'Token inválido ou expirado');
  }
}

function apenasCliente(req, res, next) {
  if (req.usuario?.tipo !== 'cliente') return naoAutorizado(res, 'Acesso apenas para clientes');
  next();
}

function apenasLoja(req, res, next) {
  if (req.usuario?.tipo !== 'loja') return naoAutorizado(res, 'Acesso apenas para lojas');
  next();
}

function apenasAdmin(req, res, next) {
  if (req.usuario?.tipo !== 'admin') return naoAutorizado(res, 'Acesso apenas para administradores');
  next();
}

module.exports = { autenticar, apenasCliente, apenasLoja, apenasAdmin };
