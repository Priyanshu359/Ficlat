const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const pool = require('../../config/db');
const authModel = require('./authModel');
const { ref } = require('joi');

function generateAccessToken(user) {
    return jwt.sign(
        {
            id: user.id,
            role: user.role,
        },
        process.env.JWT_SECRET,
        { expiresIn: '1h' }
    );
}

function generateRefreshToken() {
    return uuidv4();
}

exports.register = async ({ email, password, role }) => {
    const existing = await authModel.findUserByEmail(email);
    if (existing) {
        const err = new Error('Email already exists');
        err.status = 400;
        throw err;
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    return authModel.createUser(email, hashedPassword, role);
};

exports.login = async ({ email, password }) => {
    const user = await authModel.findUserByEmail(email);
    if (!user) {
        throw new Error('Invalid email or password');
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
        throw new Error('Invalid email or password');
    }

    const accessToken = generateAccessToken(user);
    const refreshToken = generateRefreshToken();
    await authModel.createSession(user.id, refreshToken, req.ip, req.headers['user-agent']);

    return { user, accessToken, refreshToken };
};

exports.logout = async (user, refreshToken) => {
    if (!refreshToken) {
        throw new Error('Refresh token is required for logout');
    }
    await authModel.deleteSession(user.id, refreshToken);
};

exports.refreshToken = async (refreshToken) => {
    const session = await authModel.findSession(refreshToken);
    if (!session) throw new Error('Invalid refresh token');

    const user = await authModel.findUserById(session.user_id);
    const accessToken = generateAccessToken(user);

    return { accessToken };
};

