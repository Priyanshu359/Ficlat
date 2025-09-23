const express = require('express');
const router = express.Router();
const validate = require('../../middleware/validateMiddleware');
const authController = require('./authController');
const { registerSchema, loginSchema } = require('./authValidator');
const authMiddleware = require('../../middleware/authMiddleware');

// Authentication & Session Routes
router.post('/register', validate(registerSchema), authController.register);
router.post('/login', validate(loginSchema), authController.login);
router.post('/refresh-token', authController.refreshToken);
router.post('/logout', authMiddleware, authController.logout);

router.post('/request-password-reset', authController.requestPasswordReset);
router.post('/reset-password', authController.resetPassword);

router.post('/request-email-verification', authMiddleware, authController.requestEmailVerification);
router.get('/verify-email', authController.verifyEmail);

router.get('/session/curent', authMiddleware, authController.getCurrentSession);
router.get('/sessions', authMiddleware, authController.getAllSession);
router.delete('/sessions/:sessionId', authMiddleware, authController.deleteSession);

module.exports = router;