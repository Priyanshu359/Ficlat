const pool = require('../../config/db');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

exports.findUserByEmail = async (email) => {
    const result = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
    return result.rows[0];
};

exports.findUserById = async (id) => {
    const result = await pool.query('SELECT * FROM users WHERE id = $1', [id]);
    return result.rows[0];
};

exports.createUser = async (email, passwordHash, role) => {
    const result = await pool.query(
        `INSERT INTO users (email, password_hash, role, status)
     VALUES ($1, $2, $3, 'pending_verification')
     RETURNING id, email, role, status, created_at`,
        [email, passwordHash, role]
    );
    return result.rows[0];
};

exports.createSession = async (userId, refreshToken, ip, userAgent) => {
    const refreshTokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

    const result = await pool.query(
        `INSERT INTO user_sessions (user_id, refresh_token_hash, ip_address, user_agent, expires_at)
     VALUES ($1, $2, $3, $4, $5) RETURNING id`,
        [userId, refreshTokenHash, ip, userAgent, expiresAt]
    );
    return result.rows[0];
};

exports.findSession = async (refreshToken) => {
    const refreshTokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
    const result = await pool.query(
        `SELECT * FROM user_sessions WHERE refresh_token_hash = $1 AND expires_at > NOW()`,
        [refreshTokenHash]
    );
    return result.rows[0];
};

exports.deleteSession = async (userId, refreshToken) => {
    const refreshTokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
    await pool.query(
        `DELETE FROM user_sessions WHERE user_id = $1 AND refresh_token_hash = $2`,
        [userId, refreshTokenHash]
    );
};
