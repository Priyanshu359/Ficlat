const authService = require('./authService');

exports.register = async (req, res, next) => {
    try {
        const user = await authService.register(req.body);
        res.status(201).json({ message: 'User registered successfully', user });
    } catch (error) {
        next(error);
    }
};

exports.login = async (req, res, next) => {
    try {
        const { user, accessToken, refreshToken } = await authService.login(req.body);
        res.json({ success: true, user, accessToken, refreshToken });
    } catch (error) {
        next(error);
    }
};

exports.logout = async (req, res, next) => {
    try {
        await authService.logout(req.user, req.body.refreshToken);
        res.json({ success: true, message: 'Logged out successfully' });
    }
    catch (error) {
        next(error);
    }
};

exports.refreshToken = async (req, res, next) => {
    try {
        const { accessToken } = await authService.refreshToken(req.body.refreshToken);
        res.json({ success: true, accessToken });
    } catch (error) {
        next(error);
    }
};

// PlaceHolders for other controller methods
exports.requestPasswordReset = async (req, res) => res.send(`TODO: Password reset flow`);
exports.resetPassword = async (req, res) => res.send(`TODO: Reset password `);
exports.requestEmailVerification = async (req, res) => res.send(`TODO: Request email verification flow`);
exports.verifyEmail = async (req, res) => res.send(`TODO: Verify email flow`);
exports.getCurrentSession = async (req, res) => res.json({ success: true, session: req.user });
exports.getAllSession = async (req, res) => res.send(`TODO: Get all sessions flow`);
exports.deleteSession = async (req, res) => res.send(`TODO: Delete session flow`);