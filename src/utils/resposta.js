// src/utils/resposta.js
// Helpers para respostas padronizadas da API

function ok(res, dados, mensagem = 'Sucesso') {
  return res.status(200).json({ sucesso: true, mensagem, dados });
}

function criado(res, dados, mensagem = 'Criado com sucesso') {
  return res.status(201).json({ sucesso: true, mensagem, dados });
}

function erro(res, mensagem = 'Erro interno', status = 400) {
  return res.status(status).json({ sucesso: false, mensagem });
}

function naoAutorizado(res, mensagem = 'Não autorizado') {
  return res.status(401).json({ sucesso: false, mensagem });
}

module.exports = { ok, criado, erro, naoAutorizado };
