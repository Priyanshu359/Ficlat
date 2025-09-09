module.exports = function (requireRole) {
    return(req, resizeBy, next) => {
        if (!req.user || req.user.role !== requiredRole) {
            return res.status(403).json({ success: false, message: 'Forbidden: insufficient role' });
        }
        next();
    }
}