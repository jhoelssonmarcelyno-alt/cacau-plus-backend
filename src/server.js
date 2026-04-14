const express = require('express');
const cors    = require('cors');
require('dotenv').config();
const { setupAdmin } = require('./controllers/adminController');

const app = express();
app.use(cors());
app.use(express.json());

app.use('/auth',         require('./routes/auth'));
app.use('/cliente',      require('./routes/cliente'));
app.use('/lojas',        require('./routes/loja'));
app.use('/coins',        require('./routes/coins'));
app.use('/premios',      require('./routes/premios'));
app.use('/avaliacoes',   require('./routes/avaliacoes'));
app.use('/fidelidade',   require('./routes/fidelidade'));
app.use('/tarefas',      require('./routes/tarefas'));
app.use('/campanhas',    require('./routes/campanhas'));
app.use('/notificacoes', require('./routes/notificacoes'));
app.use('/banners',      require('./routes/banners'));
app.use('/push',         require('./routes/push'));
app.use('/admin',        require('./routes/admin'));
app.use('/admin',        require('./routes/adminCoins'));

app.get('/health', (req, res) => res.json({ status: 'ok', app: 'Cacau Plus' }));
app.use((req, res) => res.status(404).json({ sucesso: false, mensagem: 'Rota não encontrada' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, async () => {
  console.log(`🍫 Cacau Plus backend rodando na porta ${PORT}`);
  await setupAdmin();
});
