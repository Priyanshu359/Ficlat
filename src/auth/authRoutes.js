const express = require('express');
const router = express.Router();
const validate = require('../../middleware/validate');
const authController = require('./authController');
const { registerSchema, loginSchema } = require('./authValidation');
const authMiddleware = require('../../middleware/authMiddleware');