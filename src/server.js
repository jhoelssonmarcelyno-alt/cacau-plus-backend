const express = require('express');
const cors    = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

app.use('/auth',       require('./routes/auth'));
app.use('/cliente',    require('./routes/cliente'));
app.use('/lojas',      require('./routes/loja'));
app.use('/coins',      require('./routes/coins'));
app.use('/premios',    require('./routes/premios'));
app.use('/avaliacoes', require('./routes/avaliacoes'));

app.get('/health', (req, res) => res.json({ status: 'ok', app: 'Cacau Plus' }));
app.use((req, res) => res.status(404).json({ sucesso: false, mensagem: 'Rota não encontrada' }));

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`🍫 Cacau Plus backend rodando na porta ${PORT}`));
