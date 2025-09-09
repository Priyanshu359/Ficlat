-- Ficlat - Industry-Grade PostgreSQL Database Schema
-- Version: 1.0
-- Author: Priyanshu
-- Date: 2025-09-08

-- This script creates the complete database structure for the Ficlat platform,
-- including tables for user management, organizations, job referrals, finance,
-- communication, and administration.

-- Enable UUID generation extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- Module 1: Core Identity & Access Management
-- =============================================================================

-- Define custom ENUM types for status fields to ensure data integrity
CREATE TYPE user_role AS ENUM ('job_seeker', 'employee', 'admin');
CREATE TYPE user_status AS ENUM ('pending_verification', 'active', 'suspended', 'deactivated');
CREATE TYPE auth_action AS ENUM ('login_success', 'login_failure', 'logout', 'password_reset_request', 'token_refresh');

-- Table: users
-- Stores the core identity for every actor on the platform.
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role user_role NOT NULL,
    status user_status NOT NULL DEFAULT 'pending_verification',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users(email);

-- Table: user_profiles
-- Contains public and private profile information.
CREATE TABLE user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    full_name VARCHAR(255) NOT NULL,
    headline VARCHAR(255),
    bio TEXT,
    avatar_url VARCHAR(255),
    location VARCHAR(255),
    linkedin_url VARCHAR(255)
);

-- Table: user_settings
-- User-configurable settings.
CREATE TABLE user_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    notification_preferences JSONB DEFAULT '{}',
    privacy_settings JSONB DEFAULT '{}',
    theme VARCHAR(50) DEFAULT 'light'
);

-- Table: user_sessions
-- Manages active user sessions for security.
CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(255) NOT NULL,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);

-- Table: auth_logs
-- Tracks authentication events for security auditing.
CREATE TABLE auth_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action auth_action NOT NULL,
    ip_address INET,
    details JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_auth_logs_user_id ON auth_logs(user_id);
CREATE INDEX idx_auth_logs_action ON auth_logs(action);

-- Table: password_resets & email_verifications
-- Securely manages tokens for account management flows.
CREATE TABLE password_resets (
    email VARCHAR(255) PRIMARY KEY,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE email_verifications (
    email VARCHAR(255) PRIMARY KEY,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Module 2: Organizations & RBAC (Role-Based Access Control)
-- =============================================================================

CREATE TYPE org_status AS ENUM ('active', 'suspended');
CREATE TYPE invitation_status AS ENUM ('pending', 'accepted', 'expired', 'revoked');

-- Table: organizations
-- Represents a company or a team account.
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    name VARCHAR(255) NOT NULL,
    website_url VARCHAR(255),
    description TEXT,
    status org_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: roles
-- Defines permission sets within an organization (e.g., Admin, Manager, Referrer).
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    UNIQUE(organization_id, name)
);

-- Table: permissions
-- Defines granular actions that can be performed.
CREATE TABLE permissions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL, -- e.g., 'job:create', 'billing:manage'
    description TEXT
);

-- Table: role_permissions
-- Junction table mapping permissions to roles.
CREATE TABLE role_permissions (
    role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Table: organization_members
-- Junction table linking users to organizations.
CREATE TABLE organization_members (
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (organization_id, user_id)
);

-- Table: invitations
-- Manages invites for users to join an organization.
CREATE TABLE invitations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    inviter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    invitee_email VARCHAR(255) NOT NULL,
    role_id INTEGER REFERENCES roles(id) ON DELETE SET NULL,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    status invitation_status NOT NULL DEFAULT 'pending',
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_invitations_invitee_email ON invitations(invitee_email);

-- =============================================================================
-- Module 3: Jobs, Resumes & Referrals
-- =============================================================================

CREATE TYPE referral_status AS ENUM (
    'pending_acceptance', 'rejected', 'in_progress', 'submitted_to_ats',
    'interviewing', 'hired', 'not_selected', 'completed', 'disputed'
);

CREATE TYPE referral_payment_status AS ENUM ('pending', 'escrow', 'released', 'refunded');

-- Table: job_postings
-- Contains all details about a job opening available for referral.
CREATE TABLE job_postings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    posted_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
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
CREATE INDEX idx_job_postings_title ON job_postings(job_title);
CREATE INDEX idx_job_postings_is_active ON job_postings(is_active);

-- Table: skills and job_skills
-- For tagging jobs with relevant skills.
CREATE TABLE skills (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE job_skills (
    job_posting_id UUID NOT NULL REFERENCES job_postings(id) ON DELETE CASCADE,
    skill_id INTEGER NOT NULL REFERENCES skills(id) ON DELETE CASCADE,
    PRIMARY KEY (job_posting_id, skill_id)
);

-- Table: referral_requests
-- The core table tracking the entire referral lifecycle.
CREATE TABLE referral_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_posting_id UUID NOT NULL REFERENCES job_postings(id) ON DELETE CASCADE,
    job_seeker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status referral_status NOT NULL DEFAULT 'pending_acceptance',
    payment_status referral_payment_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_referral_requests_job_seeker_id ON referral_requests(job_seeker_id);
CREATE INDEX idx_referral_requests_employee_id ON referral_requests(employee_id);
CREATE INDEX idx_referral_requests_status ON referral_requests(status);

-- Table: referral_status_history
-- Logs every status change for a referral for auditing.
CREATE TABLE referral_status_history (
    id BIGSERIAL PRIMARY KEY,
    referral_request_id UUID NOT NULL REFERENCES referral_requests(id) ON DELETE CASCADE,
    status referral_status NOT NULL,
    notes TEXT,
    changed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: resumes
-- Stores metadata for user-uploaded resumes.
CREATE TABLE resumes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    storage_url VARCHAR(2048) NOT NULL,
    file_size_bytes INTEGER,
    version INTEGER NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, version)
);

-- Table: resume_parsed_data
-- Stores structured data extracted from resumes by a parsing service.
CREATE TABLE resume_parsed_data (
    resume_id UUID PRIMARY KEY REFERENCES resumes(id) ON DELETE CASCADE,
    provider VARCHAR(100), -- e.g., 'affinda', 'sovren'
    raw_data JSONB,
    skills_extracted TEXT[],
    ai_match_score INTEGER,
    parsed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table: cover_letters
-- Stores cover letters attached to a specific referral request.
CREATE TABLE cover_letters (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referral_request_id UUID UNIQUE NOT NULL REFERENCES referral_requests(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Module 4: Finance & Monetization
-- =============================================================================

CREATE TYPE transaction_type AS ENUM (
    'deposit', 'withdrawal', 'referral_escrow', 'referral_payout', 'subscription_fee', 'refund', 'platform_fee'
);
CREATE TYPE transaction_status AS ENUM ('pending', 'completed', 'failed', 'canceled');
CREATE TYPE subscription_status AS ENUM ('active', 'canceled', 'past_due', 'trialing');
CREATE TYPE invoice_status AS ENUM ('draft', 'open', 'paid', 'void', 'uncollectible');
CREATE TYPE owner_type AS ENUM ('user', 'organization');

-- Table: wallets
-- Manages balances for users and organizations.
CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID NOT NULL,
    owner_type owner_type NOT NULL, -- To identify if it's a user or org wallet
    balance DECIMAL(19, 4) NOT NULL DEFAULT 0.00,
    currency VARCHAR(3) NOT NULL DEFAULT 'INR',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(owner_id, owner_type)
);

-- Table: transactions
-- An immutable log of all financial movements.
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    referral_request_id UUID REFERENCES referral_requests(id) ON DELETE SET NULL,
    amount DECIMAL(19, 4) NOT NULL,
    type transaction_type NOT NULL,
    status transaction_status NOT NULL DEFAULT 'pending',
    gateway_transaction_id VARCHAR(255),
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_transactions_wallet_id ON transactions(wallet_id);

-- Table: subscription_plans
-- Defines the available subscription tiers.
CREATE TABLE subscription_plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price_monthly DECIMAL(10, 2),
    price_yearly DECIMAL(10, 2),
    features JSONB,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Table: subscriptions
-- Tracks active subscriptions for users/orgs.
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscriber_id UUID NOT NULL,
    subscriber_type owner_type NOT NULL,
    plan_id INTEGER NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
    status subscription_status NOT NULL,
    current_period_starts_at TIMESTAMPTZ,
    current_period_ends_at TIMESTAMPTZ,
    canceled_at TIMESTAMPTZ
);
CREATE INDEX idx_subscriptions_subscriber ON subscriptions(subscriber_id, subscriber_type);

-- Table: invoices & related tables
-- For managing billing.
CREATE TABLE tax_rates (
    id SERIAL PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    rate_percentage DECIMAL(5, 2) NOT NULL,
    country_code VARCHAR(2) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    recipient_id UUID NOT NULL,
    recipient_type owner_type NOT NULL,
    status invoice_status NOT NULL DEFAULT 'draft',
    amount_due DECIMAL(19, 4) NOT NULL,
    amount_paid DECIMAL(19, 4) NOT NULL DEFAULT 0.00,
    due_date DATE,
    paid_at TIMESTAMPTZ,
    pdf_url VARCHAR(2048),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE invoice_line_items (
    id BIGSERIAL PRIMARY KEY,
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    description VARCHAR(255) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price DECIMAL(19, 4) NOT NULL,
    tax_rate_id INTEGER REFERENCES tax_rates(id) ON DELETE SET NULL
);

-- Table: payout_accounts
-- Stores bank details for employee payouts.
CREATE TABLE payout_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(100) NOT NULL, -- e.g., 'stripe', 'razorpay'
    account_details_encrypted TEXT NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- =============================================================================
-- Module 5: Communication, Community & Support
-- =============================================================================

CREATE TYPE ticket_status AS ENUM ('open', 'pending', 'resolved', 'closed');
CREATE TYPE ticket_priority AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE dispute_status AS ENUM ('open', 'under_review', 'resolved_in_favor_of_seeker', 'resolved_in_favor_of_employee', 'closed');
CREATE TYPE report_status AS ENUM ('pending', 'reviewed', 'action_taken', 'dismissed');


-- Tables for messaging
CREATE TABLE message_threads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referral_request_id UUID UNIQUE REFERENCES referral_requests(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE thread_participants (
    thread_id UUID NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_at TIMESTAMPTZ,
    PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id UUID NOT NULL REFERENCES message_threads(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_messages_thread_id ON messages(thread_id);

-- Table: notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(100) NOT NULL, -- e.g., 'new_referral_request', 'message_received'
    data JSONB,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_notifications_recipient_id ON notifications(recipient_id);

-- Table: reviews
CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referral_request_id UUID UNIQUE NOT NULL REFERENCES referral_requests(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reviewee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (reviewer_id != reviewee_id)
);
CREATE INDEX idx_reviews_reviewee_id ON reviews(reviewee_id);


-- Tables for support and moderation
CREATE TABLE support_tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject VARCHAR(255) NOT NULL,
    description TEXT,
    status ticket_status NOT NULL DEFAULT 'open',
    priority ticket_priority NOT NULL DEFAULT 'medium',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE ticket_replies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE disputes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referral_request_id UUID UNIQUE NOT NULL REFERENCES referral_requests(id) ON DELETE RESTRICT,
    claimant_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status dispute_status NOT NULL DEFAULT 'open',
    resolved_by_admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_entity_type VARCHAR(100) NOT NULL, -- e.g., 'user', 'job_posting'
    reported_entity_id UUID NOT NULL,
    reason TEXT NOT NULL,
    status report_status NOT NULL DEFAULT 'pending',
    reviewed_by_admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- Module 6: Admin & System
-- =============================================================================

-- Table: audit_logs
-- A critical log of all significant actions performed by users.
CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(255) NOT NULL,
    target_type VARCHAR(100),
    target_id UUID,
    details JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_logs_actor_user_id ON audit_logs(actor_user_id);
CREATE INDEX idx_audit_logs_target ON audit_logs(target_type, target_id);

-- --- END OF SCHEMA ---
