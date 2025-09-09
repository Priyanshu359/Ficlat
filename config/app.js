const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const helmet = require('helmet');
const errorHandler = require('../middleware/errorHandler');


require('dotenv').config();

const routes = require('../src/routes');

const app = express();

//Global Middlewares
app.use(express.json());
app.use(cors());
app.use(morgan('dev'));
app.use(helmet());
app.use(errorHandler);

// Routes
app.use('/api/v1', routes);

// Health Check Endpoint
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'OK', message: 'Server is healthy', timestamp: new Date() });
});

// Global Error Handler 
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ status: 'error', message: 'Something went wrong!' });
});

module.exports = app;