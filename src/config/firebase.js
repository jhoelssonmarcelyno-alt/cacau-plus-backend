// src/config/firebase.js
// Inicializa Firebase Admin SDK para envio de push notifications

let admin;

function getAdmin() {
  if (admin) return admin;
  try {
    admin = require('firebase-admin');
    const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT
      ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
      : null;

    if (!serviceAccount) {
      console.warn('⚠️  FIREBASE_SERVICE_ACCOUNT não configurado — push desativado');
      return null;
    }

    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
    }
    return admin;
  } catch (e) {
    console.error('Erro ao inicializar Firebase:', e.message);
    return null;
  }
}

async function enviarPush(tokens, titulo, mensagem, dados = {}) {
  const a = getAdmin();
  if (!a || !tokens.length) return;

  try {
    const message = {
      notification: { title: titulo, body: mensagem },
      data: { ...dados },
      tokens,
    };
    const res = await a.messaging().sendEachForMulticast(message);
    console.log(`Push enviado: ${res.successCount} ok, ${res.failureCount} falhas`);
    return res;
  } catch (e) {
    console.error('Erro ao enviar push:', e.message);
  }
}

module.exports = { enviarPush };
