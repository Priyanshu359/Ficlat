-- Ficlat - PostgreSQL Database Schema (DEV-friendly: SERIAL primary keys)
-- Version: 1.1
-- Author: Priyanshu (cleaned)
-- Date: 2025-09-08 (updated)

-- Enable UUID extension (kept for any future use)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- Module 1: Core Identity & Access Management
-- =============================================================================

-- Define custom ENUM types for status fields to ensure data integrity
CREATE TYPE IF NOT EXISTS user_role AS ENUM ('job_seeker', 'employee', 'admin');
CREATE TYPE IF NOT EXISTS user_status AS ENUM ('pending_verification', 'active', 'suspended', 'deactivated');
CREATE TYPE IF NOT EXISTS auth_action AS ENUM ('login_success', 'login_failure', 'logout', 'password_reset_request', 'token_refresh');

-- Table: users
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role user_role NOT NULL,
    status user_status NOT NULL DEFAULT 'pending_verification',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Table: user_profiles
CREATE TABLE IF NOT EXISTS user_profiles (
    user_id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    full_name VARCHAR(255) NOT NULL,
    headline VARCHAR(255),
    bio TEXT,
    avatar_url VARCHAR(255),
    location VARCHAR(255),
    linkedin_url VARCHAR(255)
);

-- Table: user_settings
CREATE TABLE IF NOT EXISTS user_settings (
    user_id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    notification_preferences JSONB DEFAULT '{}',
    privacy_settings JSONB DEFAULT '{}',
    theme VARCHAR(50) DEFAULT 'light'
);

-- Table: user_sessions
CREATE TABLE IF NOT EXISTS user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(255) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);

-- Table: auth_logs
CREATE TABLE IF NOT EXISTS auth_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE SET NULL,
    action auth_action NOT NULL,
    ip_address INET,
    details JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_auth_logs_user_id ON auth_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_logs_action ON auth_logs(action);

-- Table: password_resets & email_verifications
CREATE TABLE IF NOT EXISTS password_resets (
    email VARCHAR(255) PRIMARY KEY,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS email_verifications (
    email VARCHAR(255) PRIMARY KEY,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Module 2: Organizations & RBAC (Role-Based Access Control)
-- =============================================================================

CREATE TYPE IF NOT EXISTS org_status AS ENUM ('active', 'suspended');
CREATE TYPE IF NOT EXISTS invitation_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');

-- Table: organizations
CREATE TABLE IF NOT EXISTS organizations (
    id SERIAL PRIMARY KEY,
    owner_id INT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    name VARCHAR(255) NOT NULL,
    website_url VARCHAR(255),
    description TEXT,
    status org_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: roles
CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    organization_id INT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    UNIQUE(organization_id, name)
);

-- Table: permissions
CREATE TABLE IF NOT EXISTS permissions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

-- Table: role_permissions
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Table: organization_members
CREATE TABLE IF NOT EXISTS organization_members (
    organization_id INT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (organization_id, user_id)
);

-- Table: invitations
CREATE TABLE IF NOT EXISTS invitations (
    id SERIAL PRIMARY KEY,
    organization_id INT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    inviter_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invitee_email VARCHAR(255) NOT NULL,
    role_id INTEGER REFERENCES roles(id) ON DELETE SET NULL,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    status invitation_status NOT NULL DEFAULT 'pending',
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invitations_invitee_email ON invitations(invitee_email);

-- =============================================================================
-- Module 3: Jobs, Resumes & Referrals
-- =============================================================================

CREATE TYPE IF NOT EXISTS referral_status AS ENUM (
    'pending_acceptance', 'rejected', 'in_progress', 'submitted_to_ats',
    'interviewing', 'hired', 'not_selected', 'completed', 'disputed'
);

CREATE TYPE IF NOT EXISTS referral_payment_status AS ENUM ('pending', 'escrow', 'released', 'refunded');

-- Table: job_postings
CREATE TABLE IF NOT EXISTS job_postings (
    id SERIAL PRIMARY KEY,
    posted_by_user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    organization_id INT REFERENCES organizations(id) ON DELETE CASCADE,
    job_title VARCHAR(255) NOT NULL,
    job_description TEXT NOT NULL,
    job_url VARCHAR(2048),
    location VARCHAR(255),
    referral_fee DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'INR',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_job_postings_title ON job_postings(job_title);
CREATE INDEX IF NOT EXISTS idx_job_postings_is_active ON job_postings(is_active);

-- Table: skills and job_skills
CREATE TABLE IF NOT EXISTS skills (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS job_skills (
    job_posting_id INT NOT NULL REFERENCES job_postings(id) ON DELETE CASCADE,
    skill_id INTEGER NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
    PRIMARY KEY (job_posting_id, skill_id)
);

-- Table: referral_requests
CREATE TABLE IF NOT EXISTS referral_requests (
    id SERIAL PRIMARY KEY,
    job_posting_id INT NOT NULL REFERENCES job_postings(id) ON DELETE CASCADE,
    job_seeker_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status referral_status NOT NULL DEFAULT 'pending_acceptance',
    payment_status referral_payment_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_referral_requests_job_seeker_id ON referral_requests(job_seeker_id);
CREATE INDEX IF NOT EXISTS idx_referral_requests_employee_id ON referral_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_referral_requests_status ON referral_requests(status);

-- Table: referral_status_history
CREATE TABLE IF NOT EXISTS referral_status_history (
    id BIGSERIAL PRIMARY KEY,
    referral_request_id INT NOT NULL REFERENCES referral_requests(id) ON DELETE CASCADE,
    status referral_status NOT NULL,
    notes TEXT,
    changed_by_user_id INT REFERENCES users(id) ON DELETE SET NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: resumes
CREATE TABLE IF NOT EXISTS resumes (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    storage_url VARCHAR(2048) NOT NULL,
    file_size_bytes INTEGER,
    version INTEGER NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, version)
);

-- Table: resume_parsed_data
CREATE TABLE IF NOT EXISTS resume_parsed_data (
    resume_id INT PRIMARY KEY REFERENCES resumes(id) ON DELETE CASCADE,
    provider VARCHAR(100),
    raw_data JSONB,
    skills_extracted TEXT[],
    ai_match_score INTEGER,
    parsed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: cover_letters
CREATE TABLE IF NOT EXISTS cover_letters (
    id SERIAL PRIMARY KEY,
    referral_request_id INT UNIQUE NOT NULL REFERENCES referral_requests(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Module 4: Finance & Monetization
-- =============================================================================

CREATE TYPE IF NOT EXISTS transaction_type AS ENUM (
    'deposit', 'withdrawal', 'referral_escrow', 'referral_payout', 'subscription_fee', 'refund', 'platform_fee'
);
CREATE TYPE IF NOT EXISTS transaction_status AS ENUM ('pending', 'completed', 'failed', 'canceled');
CREATE TYPE IF NOT EXISTS subscription_status AS ENUM ('active', 'canceled', 'past_due', 'trialing');
CREATE TYPE IF NOT EXISTS invoice_status AS ENUM ('draft', 'open', 'paid', 'void', 'uncollectible');
CREATE TYPE IF NOT EXISTS owner_type AS ENUM ('user', 'organization');

-- Table: wallets
CREATE TABLE IF NOT EXISTS wallets (
    id SERIAL PRIMARY KEY,
    owner_id INT NOT NULL,
    owner_type owner_type NOT NULL,
    balance DECIMAL(19, 4) NOT NULL DEFAULT 0.00,
    currency VARCHAR(3) NOT NULL DEFAULT 'INR',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(owner_id, owner_type)
);

-- Table: transactions
CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    wallet_id INT NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    referral_request_id INT REFERENCES referral_requests(id) ON DELETE SET NULL,
    amount DECIMAL(19, 4) NOT NULL,
    type transaction_type NOT NULL,
    status transaction_status NOT NULL DEFAULT 'pending',
    gateway_transaction_id VARCHAR(255),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_transactions_wallet_id ON transactions(wallet_id);

-- Table: subscription_plans
CREATE TABLE IF NOT EXISTS subscription_plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price_monthly DECIMAL(10, 2),
    price_yearly DECIMAL(10, 2),
    features JSONB,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Table: subscriptions
CREATE TABLE IF NOT EXISTS subscriptions (
    id SERIAL PRIMARY KEY,
    subscriber_id INT NOT NULL,
    subscriber_type owner_type NOT NULL,
    plan_id INTEGER NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
    status subscription_status NOT NULL,
    current_period_starts_at TIMESTAMPTZ,
    current_period_ends_at TIMESTAMPTZ,
    canceled_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_subscriptions_subscriber ON subscriptions(subscriber_id, subscriber_type);

-- Table: tax_rates, invoices and invoice_line_items
CREATE TABLE IF NOT EXISTS tax_rates (
    id SERIAL PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    rate_percentage DECIMAL(5, 2) NOT NULL,
    country_code VARCHAR(2) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS invoices (
    id SERIAL PRIMARY KEY,
    subscription_id INT REFERENCES subscriptions(id) ON DELETE SET NULL,
    recipient_id INT NOT NULL,
    recipient_type owner_type NOT NULL,
    status invoice_status NOT NULL DEFAULT 'draft',
    amount_due DECIMAL(19, 4) NOT NULL,
    amount_paid DECIMAL(19, 4) NOT NULL DEFAULT 0.00,
    due_date DATE,
    paid_at TIMESTAMPTZ,
    pdf_url VARCHAR(2048),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS invoice_line_items (
    id BIGSERIAL PRIMARY KEY,
    invoice_id INT NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    description VARCHAR(255) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price DECIMAL(19, 4) NOT NULL,
    tax_rate_id INTEGER REFERENCES tax_rates(id) ON DELETE SET NULL
);

-- Table: payout_accounts
CREATE TABLE IF NOT EXISTS payout_accounts (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(100) NOT NULL,
    account_details_encrypted TEXT NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Module 5: Communication, Community & Support
-- =============================================================================

CREATE TYPE IF NOT EXISTS ticket_status AS ENUM ('open', 'pending', 'resolved', 'closed');
CREATE TYPE IF NOT EXISTS ticket_priority AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE IF NOT EXISTS dispute_status AS ENUM ('open', 'under_review', 'resolved_in_favor_of_seeker', 'resolved_in_favor_of_employee', 'closed');
CREATE TYPE IF NOT EXISTS report_status AS ENUM ('pending', 'reviewed', 'action_taken', 'dismissed');

-- Tables for messaging
CREATE TABLE IF NOT EXISTS message_threads (
    id SERIAL PRIMARY KEY,
    referral_request_id INT UNIQUE REFERENCES referral_requests(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS thread_participants (
    thread_id INT NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ,
    PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    thread_id INT NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    sender_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_messages_thread_id ON messages(thread_id);

-- Table: notifications
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    recipient_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(100) NOT NULL,
    data JSONB,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_id ON notifications(recipient_id);

-- Table: reviews
CREATE TABLE IF NOT EXISTS reviews (
    id SERIAL PRIMARY KEY,
    referral_request_id INT UNIQUE NOT NULL REFERENCES referral_requests(id) ON DELETE CASCADE,
    reviewer_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reviewee_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (reviewer_id != reviewee_id)
);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewee_id ON reviews(reviewee_id);

-- Tables for support and moderation
CREATE TABLE IF NOT EXISTS support_tickets (
    id SERIAL PRIMARY KEY,
    requester_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject VARCHAR(255) NOT NULL,
    description TEXT,
    status ticket_status NOT NULL DEFAULT 'open',
    priority ticket_priority NOT NULL DEFAULT 'medium',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS ticket_replies (
    id SERIAL PRIMARY KEY,
    ticket_id INT NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    author_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS disputes (
    id SERIAL PRIMARY KEY,
    referral_request_id INT UNIQUE NOT NULL REFERENCES referral_requests(id) ON DELETE RESTRICT,
    claimant_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status dispute_status NOT NULL DEFAULT 'open',
    resolved_by_admin_id INT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS reports (
    id SERIAL PRIMARY KEY,
    reporter_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_entity_type VARCHAR(100) NOT NULL,
    reported_entity_id INT NOT NULL,
    reason TEXT NOT NULL,
    status report_status NOT NULL DEFAULT 'pending',
    reviewed_by_admin_id INT REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Module 6: Admin & System
-- =============================================================================

CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    actor_user_id INT REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(255) NOT NULL,
    target_type VARCHAR(100),
    target_id INT,
    details JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_user_id ON audit_logs(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_target ON audit_logs(target_type, target_id);

-- --- END OF SCHEMA ---
