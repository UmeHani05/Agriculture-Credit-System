-- ============================================================
-- AGRICULTURAL CREDIT & FINANCIAL MANAGEMENT SYSTEM
-- Corrected Schema
-- ============================================================

-- ============================================================
-- UUID V7 FUNCTIONS (source: https://gist.github.com/edr3x/ba286f20f8bb35205bf750209d621b3b)
-- ============================================================

CREATE OR REPLACE FUNCTION gen_uuidv7() RETURNS uuid AS $$
BEGIN
    RETURN gen_uuidv7(clock_timestamp());
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION gen_uuidv7(p_timestamp TIMESTAMP WITH TIME ZONE) RETURNS uuid AS $$
DECLARE
    v_time         numeric := null;
    v_unix_t       numeric := null;
    v_rand_a       numeric := null;
    v_rand_b       numeric := null;
    v_unix_t_hex   varchar := null;
    v_rand_a_hex   varchar := null;
    v_rand_b_hex   varchar := null;
    v_output_bytes bytea   := null;
    c_milli_factor numeric := 10^3::numeric;
    c_micro_factor numeric := 10^6::numeric;
    c_scale_factor numeric := 4.096::numeric;
    c_version      bit(64) := x'0000000000007000';
    c_variant      bit(64) := x'8000000000000000';
BEGIN
    v_time       := extract(epoch FROM p_timestamp);
    v_unix_t     := trunc(v_time * c_milli_factor);
    v_rand_a     := ((v_time * c_micro_factor) - (v_unix_t * c_milli_factor)) * c_scale_factor;
    v_rand_b     := random()::numeric * 2^62::numeric;
    v_unix_t_hex := lpad(to_hex(v_unix_t::bigint), 12, '0');
    v_rand_a_hex := lpad(to_hex((v_rand_a::bigint::bit(64) | c_version)::bigint), 4, '0');
    v_rand_b_hex := lpad(to_hex((v_rand_b::bigint::bit(64) | c_variant)::bigint), 16, '0');
    v_output_bytes := decode(v_unix_t_hex || v_rand_a_hex || v_rand_b_hex, 'hex');
    RETURN encode(v_output_bytes, 'hex')::uuid;
END $$ LANGUAGE plpgsql;


-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE app_status       AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE loan_status      AS ENUM ('Active', 'Closed');
CREATE TYPE payment_method   AS ENUM ('Cash', 'Online');
CREATE TYPE trans_type       AS ENUM ('Loan', 'Partially Paid','Payment');
CREATE TYPE trans_status     AS ENUM ('Completed', 'Pending');
CREATE TYPE user_role        AS ENUM ('Admin', 'Loan Officer', 'Credit Analyst');
CREATE TYPE invoice_status   AS ENUM ('Paid', 'Overdue');
CREATE TYPE fraud_status AS ENUM ('Detected', 'Reviewed', 'Dismissed');
CREATE TYPE land_type        AS ENUM ('Irrigated', 'Non-Irrigated', 'Pasture');
CREATE TYPE claim_collateral AS ENUM ('Claimed', 'Non-Claimed', 'Partially Claimed');


-- ============================================================
-- EXTENSIONS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ============================================================
-- INDEPENDENT ENTITIES
-- ============================================================

CREATE TABLE Banks (
    bank_id              UUID         PRIMARY KEY DEFAULT gen_uuidv7(),
    bank_name            VARCHAR(150) NOT NULL UNIQUE,
    headquarters_address VARCHAR(255),
    -- branch_id            VARCHAR(50)  NOT NULL UNIQUE, causes voilation of Norm.
    contact_number       VARCHAR(20)
);
CREATE TABLE Branches(
  branch_id VARCHAR(50)  NOT NULL UNIQUE,
  bank_id UUID NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
  branch_address VARCHAR(255),
  branch_code integer
);
CREATE TABLE UserAccounts (
    user_id       UUID      PRIMARY KEY DEFAULT gen_uuidv7(),
    bank_id       UUID      NOT NULL REFERENCES Banks(bank_id) ON DELETE CASCADE,
    username      TEXT      NOT NULL UNIQUE,
    role          user_role NOT NULL,
    password_hash TEXT      NOT NULL
);
CREATE TABLE ACCOUNTS();
CREATE TABLE Farmer (
    farmer_id         UUID         PRIMARY KEY DEFAULT gen_uuidv7(),
    name              VARCHAR(150) NOT NULL,
    cnic              VARCHAR(15)  NOT NULL UNIQUE,
    phone             VARCHAR(20),
    address           TEXT,
    registration_date DATE         NOT NULL DEFAULT CURRENT_DATE,
    eligibility       BOOLEAN,
    fraud_alert       BOOLEAN      NOT NULL DEFAULT FALSE,--controled denormalization--cause transitive dependency
    credit_history    BOOLEAN,
    bank_id UUID NOT NULL REFERENCES Banks(bank_id) ON DELETE RESTRICT
);

CREATE TABLE farmer_finance (
    farmer_finance_id   UUID      PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id           UUID          NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    reported_date       DATE          NOT NULL DEFAULT CURRENT_DATE,
    annual_revenue      NUMERIC(15,2),
    operating_expenses  NUMERIC(15,2),
    -- net_income          NUMERIC(15,2),  -- used in ROA: net_income / total_assets-- not INDEPENDENT --cause voilation of #NF
    total_assets        NUMERIC(15,2),
    cash_on_hand        NUMERIC(15,2),
    current_assets      NUMERIC(15,2),
    current_liabilities NUMERIC(15,2),
    total_debt          NUMERIC(15,2),
    annual_debt_service NUMERIC(15,2),
    application_id UUID REFERENCES LoanApplication(application_id) ON DELETE SET NULL
    CONSTRAINT uq_farmer_finance_date UNIQUE (farmer_id, reported_date)-- to ensure the credibility
);


CREATE TABLE RiskScore (
    risk_id           UUID       PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id         UUID          NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    sector_risk_value NUMERIC(5,2)  NOT NULL,
    governance_value  NUMERIC(5,2)  NOT NULL,
    is_in_arrears     BOOLEAN       NOT NULL DEFAULT FALSE,
    calculated_date   DATE          NOT NULL DEFAULT CURRENT_DATE,
    remarks           TEXT
);


-- ============================================================
-- DEPENDENT ENTITIES
-- ============================================================
CREATE TABLE LoanApplication (
    application_id     UUID          PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id          UUID          NOT NULL REFERENCES Farmer(farmer_id) ON DELETE RESTRICT,
    requested_amount   NUMERIC(15,2) NOT NULL CHECK (requested_amount > 0),
    purpose            TEXT,
    fraud_alert        BOOLEAN       NOT NULL DEFAULT FALSE,
    application_date   DATE          NOT NULL DEFAULT CURRENT_DATE,
    created_at         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_application app_status    NOT NULL DEFAULT 'Pending',
    
);

CREATE TABLE Loan (
    loan_id         UUID          PRIMARY KEY DEFAULT gen_uuidv7(),
    application_id  UUID          NOT NULL UNIQUE REFERENCES LoanApplication(application_id) ON DELETE RESTRICT,
    bank_id         UUID          NOT NULL REFERENCES Banks(bank_id) ON DELETE RESTRICT,
    approved_amount NUMERIC(15,2) NOT NULL CHECK (approved_amount > 0),
    interest_rate   NUMERIC(5,2)  NOT NULL CHECK (interest_rate >= 0),
    start_date      DATE          NOT NULL,
    end_date        DATE          NOT NULL,
    status_loan     loan_status   NOT NULL DEFAULT 'Active',
    CONSTRAINT chk_loan_dates CHECK (end_date > start_date)
);

CREATE TABLE Collateral (
    collateral_id    UUID             PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id        UUID             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    loan_id          UUID             NOT NULL REFERENCES Loan(loan_id) ON DELETE CASCADE,
    land_value       NUMERIC(15,2)    NOT NULL CHECK (land_value > 0),
    land_type        land_type        NOT NULL,
    claim_collateral claim_collateral NOT NULL DEFAULT 'Non-Claimed'
);

CREATE TABLE Payment (
    payment_id     UUID           PRIMARY KEY DEFAULT gen_uuidv7(),
    loan_id        UUID           NOT NULL REFERENCES Loan(loan_id) ON DELETE RESTRICT,
    amount_paid    NUMERIC(15,2)  NOT NULL CHECK (amount_paid > 0),
    payment_date   DATE           NOT NULL DEFAULT CURRENT_DATE,
    payment_method payment_method NOT NULL,
    created_at     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE Transaction (
    transaction_id UUID          PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id      UUID          NOT NULL REFERENCES Farmer(farmer_id) ON DELETE RESTRICT,
    loan_id        UUID          REFERENCES Loan(loan_id) ON DELETE SET NULL,
    transaction_type           trans_type    NOT NULL,
    amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    transaction_date           DATE          NOT NULL DEFAULT CURRENT_DATE,
    transferred_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_trans   trans_status  NOT NULL DEFAULT 'Pending'
);
-- CREATE SEQUENCE invoice_seq START 1000;

-- -- Then in backend or as a default:
-- DEFAULT 'INV-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' || LPAD(NEXTVAL('invoice_seq')::TEXT, 5, '0
CREATE TABLE Invoice (
    invoice_id     UUID           PRIMARY KEY DEFAULT gen_uuidv7(),
    invoice_no     VARCHAR(50)    NOT NULL UNIQUE,
    
    farmer_id      UUID           NOT NULL REFERENCES Farmer(farmer_id) ON DELETE RESTRICT,
    loan_id        UUID           REFERENCES Loan(loan_id) ON DELETE SET NULL,
    payment_id     UUID           REFERENCES Payment(payment_id) ON DELETE SET NULL,
    amount         NUMERIC(15,2)  NOT NULL CHECK (amount > 0),
    issue_date     DATE           NOT NULL DEFAULT CURRENT_DATE,
    due_date       DATE           NOT NULL,
    status_invoice invoice_status NOT NULL DEFAULT 'Overdue',
    CONSTRAINT chk_invoice_dates CHECK (due_date >= issue_date)
);

CREATE TABLE FraudAlert (
    alert_id       UUID         PRIMARY KEY DEFAULT gen_uuidv7(),
    transaction_id UUID         REFERENCES Transaction(transaction_id) ON DELETE CASCADE,
    application_id UUID         REFERENCES LoanApplication(application_id) ON DELETE CASCADE,
    reason         TEXT         NOT NULL,
    flag_date      DATE         NOT NULL DEFAULT CURRENT_DATE,
    status_fraud   fraud_status NOT NULL DEFAULT 'Detected',
    CONSTRAINT chk_fraud_source CHECK (--check whether the falg is DEFAULT or calculated
        transaction_id IS NOT NULL OR application_id IS NOT NULL
    )
);

-- ============================================================
-- Role Based Access
-- ============================================================
CREATE ROLE loan_officer_role;
CREATE ROLE credit_analyst_role;
CREATE ROLE admin_role;
CREATE ROLE financial_analyst;
--permissions
GRANT SELECT ON Farmer, LoanApplication, Loan, Payment TO loan_officer_role;
GRANT INSERT, UPDATE ON LoanApplication, Payment TO loan_officer_role;
GRANT SELECT ON farmer_finance, RiskScore, risk_assessment_mof TO credit_analyst_role;
GRANT SELECT,DELETE ON farmer_finance,Farmer,Payment TO financial_analyst;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin_role;
-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_useraccounts_bank     ON UserAccounts(bank_id);
CREATE INDEX idx_useraccounts_role     ON UserAccounts(role);
CREATE INDEX idx_riskscore_farmer      ON RiskScore(farmer_id);
CREATE INDEX idx_riskscore_date        ON RiskScore(calculated_date);
CREATE INDEX idx_loanapp_farmer        ON LoanApplication(farmer_id);
CREATE INDEX idx_loanapp_status        ON LoanApplication(status_application);
CREATE INDEX idx_loanapp_date          ON LoanApplication(application_date);
CREATE INDEX idx_loan_application      ON Loan(application_id);
CREATE INDEX idx_loan_bank             ON Loan(bank_id);
CREATE INDEX idx_loan_status           ON Loan(status_loan);
CREATE INDEX idx_collateral_farmer     ON Collateral(farmer_id);
CREATE INDEX idx_collateral_loan       ON Collateral(loan_id);
CREATE INDEX idx_collateral_claim      ON Collateral(claim_collateral);
CREATE INDEX idx_payment_loan          ON Payment(loan_id);
CREATE INDEX idx_payment_date          ON Payment(payment_date);
CREATE INDEX idx_transaction_farmer    ON Transaction(farmer_id);
CREATE INDEX idx_transaction_loan      ON Transaction(loan_id);       -- new
CREATE INDEX idx_transaction_status    ON Transaction(status_trans);
CREATE INDEX idx_transaction_date      ON Transaction(transaction_date);--new
CREATE INDEX idx_invoice_farmer        ON Invoice(farmer_id);
CREATE INDEX idx_invoice_loan          ON Invoice(loan_id);           -- new
CREATE INDEX idx_invoice_status        ON Invoice(status_invoice);
CREATE INDEX idx_invoice_due           ON Invoice(due_date);
CREATE INDEX idx_fraud_transaction     ON FraudAlert(transaction_id);
CREATE INDEX idx_fraud_application     ON FraudAlert(application_id); -- new
CREATE INDEX idx_fraud_status          ON FraudAlert(status_fraud);
CREATE INDEX idx_fraud_date            ON FraudAlert(flag_date);
CREATE INDEX idx_farmer_finance_farmer ON farmer_finance(farmer_id);
CREATE INDEX idx_farmer_finance_date   ON farmer_finance(reported_date);


-- ============================================================
-- TRIGGERS: updated_at auto-update
-- When LOAN APPLICATION, PAYEMENT, TRANSACTION is updated
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_loanapp_updated_at
    BEFORE UPDATE ON LoanApplication
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_payment_updated_at
    BEFORE UPDATE ON Payment
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_transaction_updated_at
    BEFORE UPDATE ON Transaction
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- TRIGGER: Fraud Detection
-- ============================================================

CREATE OR REPLACE FUNCTION detect_fraud()
RETURNS TRIGGER AS $$
DECLARE
    avg_amount NUMERIC;
BEGIN
    SELECT COALESCE(AVG(amount), 0)
    INTO avg_amount
    FROM Transaction
    WHERE farmer_id = NEW.farmer_id;

    IF NEW.amount > GREATEST(avg_amount * 2, 30000) THEN
        INSERT INTO FraudAlert (transaction_id, reason, status_fraud)
        VALUES (NEW.transaction_id, 'Suspicious transaction detected', 'Detected');
    UPDATE Farmer-- this will update the farmer's fraud alert frequently
    SET fraud_alert=TRUE
    WHERE farmer_id=NEW.farmer_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER fraud_trigger
    AFTER INSERT ON Transaction
    FOR EACH ROW EXECUTE FUNCTION detect_fraud();

-- ============================================================
-- VIEW: Risk Assessment (Ministry of Finance Pakistan)
-- Weight normalization fixed so overall_risk_score lands in 1.0–4.0 range
--         Financial profile weights (10+10+10+15+10=55) normalized by dividing by 55
--         Business profile weights (20+15=35) normalized by dividing by 35
--         Then: financial_normalized * 0.55 + business_normalized * 0.45
-- ============================================================

CREATE VIEW risk_assessment_mof AS
WITH 
layer_1_ratio_calculation AS (
    SELECT
        f.application_id,
        r.is_in_arrears,
        -- Financial Ratios
        (ff.annual_revenue - ff.operating_expenses) AS net_income
        (ff.annual_revenue - ff.operating_expenses) / NULLIF(ff.annual_revenue, 0)      
        AS ebitda_margin,
        net_income / NULLIF(ff.total_assets, 0)                                       
        AS roa,
        ff.current_assets / NULLIF(ff.current_liabilities, 0)                          
        AS current_ratio,
        ff.total_debt / NULLIF(c.land_value - ff.total_debt, 0)                        
        AS de_ratio,
        (ff.annual_revenue - ff.operating_expenses) / NULLIF(ff.annual_debt_service, 0) 
        AS dscr,

        -- Business Inputs
        r.sector_risk_value,
        r.governance_value

    FROM LoanApplication f
    -- there is dupliaction of rows 
    JOIN (--we are making sure that a recent risk score corresponds to a framer.
        SELECT DISTINCT ON (farmer_id) *
        FROM farmer_finance
        ORDER BY  farmer_id, reported_date DESC
        ) ff ON f.farmer_id=ff.farmer_id
    
    JOIN Collateral c ON c.loan_id = (
        SELECT l.loan_id
        FROM Loan l
        WHERE l.application_id = f.application_id
        LIMIT 1
    )
    JOIN (
        SELECT DISTINCT ON (farmer_id)*
        FROM RiskScore
        ORDER BY farmer_id,calculated_date DESC
        ) r ON f.farmer_id=r.farmer_id
),
layer_2_score_calculation AS (
    SELECT
        application_id,

        -- EBITDA Margin Score
        CASE
            WHEN is_in_arrears         THEN 4  
            WHEN ebitda_margin >= 0.50 THEN 1
            WHEN ebitda_margin >= 0.30 THEN 2
            WHEN ebitda_margin >= 0.10 THEN 3
            ELSE 4
        END AS profitability_score_ebitda_margin,

        CASE
            WHEN roa >= 0.20                    THEN 1
            WHEN roa >= 0.10 AND roa < 0.20     THEN 2
            WHEN roa >= 0.05 AND roa < 0.10     THEN 3
            ELSE 4
        END AS profitability_score_roa,

        -- Current Ratio Score 
        CASE
            WHEN current_ratio >= 1.20                           THEN 1
            WHEN current_ratio >= 1.00 AND current_ratio < 1.20  THEN 2
            WHEN current_ratio >= 0.80 AND current_ratio < 1.00  THEN 3
            ELSE 4
        END AS liquidity_score_current_ratio,

        -- Debt-to-Equity Ratio Score
        CASE
            WHEN de_ratio < 0.40                          THEN 1
            WHEN de_ratio >= 0.40 AND de_ratio < 0.80     THEN 2
            WHEN de_ratio >= 0.80 AND de_ratio < 1.20     THEN 3
            ELSE 4
        END AS solvency_score_de_ratio,

        -- DSCR Score
        CASE
            WHEN dscr > 1.50                       THEN 1
            WHEN dscr >= 1.20 AND dscr <= 1.50     THEN 2
            WHEN dscr >= 1.00 AND dscr <  1.20     THEN 3
            ELSE 4
        END AS debt_service_coverage_score_dscr,

        -- Governance Score 
        CASE
            WHEN governance_value >= 10                            THEN 1
            WHEN governance_value >= 5  AND governance_value < 10  THEN 2
            WHEN governance_value >= 2  AND governance_value < 5   THEN 3
            ELSE 4
        END AS governance_score,

        -- Sector Risk Score
        CASE
            WHEN sector_risk_value >= 8                               THEN 1
            WHEN sector_risk_value >= 5 AND sector_risk_value < 8     THEN 2
            WHEN sector_risk_value >= 3 AND sector_risk_value < 5     THEN 3
            ELSE 4
        END AS sector_risk_score

    FROM layer_1_ratio_calculation
),
layer_3_final_scores AS(
SELECT
    application_id,

    -- Financial Profile: raw weights are 10,10,10,15,10 (sum=55). Divide each by 55.
    -- This ensures the sub-score itself is in 1.0–4.0 range before applying 55% weight.
    ROUND(
        profitability_score_ebitda_margin * (10.0 / 55) +
        profitability_score_roa           * (10.0 / 55) +
        liquidity_score_current_ratio     * (10.0 / 55) +
        solvency_score_de_ratio           * (15.0 / 55) +
        debt_service_coverage_score_dscr  * (10.0 / 55), 2) AS financial_profile_score,

    -- Business Profile: raw weights are 20,15 (sum=35). Divide each by 35.
    ROUND(
        sector_risk_score * (20.0 / 35) +
        governance_score  * (15.0 / 35), 2) AS business_profile_score,

    -- Overall Risk Score: financial * 55% + business * 45%
    -- Result will correctly land in the 1.0–4.0 range
    ROUND(
        (
            profitability_score_ebitda_margin * (10.0 / 55) +
            profitability_score_roa           * (10.0 / 55) +
            liquidity_score_current_ratio     * (10.0 / 55) +
            solvency_score_de_ratio           * (15.0 / 55) +
            debt_service_coverage_score_dscr  * (10.0 / 55)
        ) * 0.55
        +
        (
            sector_risk_score * (20.0 / 35) +
            governance_score  * (15.0 / 35)
        ) * 0.45
    , 2) AS overall_risk_score
    FROM layer_2_score_calculation
)
SELECT
    -- Risk Level Label (Ministry of Finance Pakistan ranges)
    application_id,
    financial_profile_score,
    business_profile_score,
    overall_risk_score,
    CASE
       WHEN overall_risk_score BETWEEN 1.0 and 1.4 THEN 'Low Risk'
       WHEN overall_risk_score BETWEEN 1.5 and 2.4 THEN 'Moderate Risk'
       WHEN overall_risk_score BETWEEN 1.0 and 1.4 THEN 'Elevated Risk'
       Else 'High Risk'
    END AS risk_level

FROM layer_3_final_scores;


-- ============================================================
-- VIEW: Invoice Aging Analysis
-- 
-- ============================================================

CREATE VIEW invoice_aging_analysis AS
SELECT
    f.name                          AS farmer_name,
    f.cnic,
    i.invoice_no,
    i.amount,
    i.issue_date,
    i.due_date,
    CURRENT_DATE - i.issue_date     AS days_since_issued,
    GREATEST(CURRENT_DATE - i.due_date, 0) AS days_overdue,
    i.status_invoice,
    CASE
        WHEN i.status_invoice = 'Paid'            THEN 'Paid'
        WHEN CURRENT_DATE <= i.due_date           THEN 'Current'
        WHEN CURRENT_DATE - i.due_date <= 30      THEN '1–30 Days Overdue'
        WHEN CURRENT_DATE - i.due_date <= 60      THEN '31–60 Days Overdue'
        WHEN CURRENT_DATE - i.due_date <= 90      THEN '61–90 Days Overdue'
        ELSE                                           'Over 90 Days Overdue'
    END AS aging_bracket
FROM Invoice i
JOIN Farmer f ON i.farmer_id = f.farmer_id
ORDER BY days_overdue DESC NULLS LAST;


-- ============================================================
-- VIEW: Outstanding Balance Report
-- ============================================================

CREATE VIEW outstanding_balance_report AS
SELECT
    f.farmer_id,
    f.name                              AS farmer_name,
    f.cnic,
    f.phone,
    COUNT(i.invoice_id)                 AS total_overdue_invoices,
    SUM(i.amount)                       AS total_outstanding_amount,
    MIN(i.due_date)                     AS oldest_due_date,
    CURRENT_DATE - MIN(i.due_date)      AS max_days_overdue
FROM Farmer f
JOIN Invoice i ON f.farmer_id = i.farmer_id
WHERE i.status_invoice = 'Overdue'
GROUP BY f.farmer_id, f.name, f.cnic, f.phone
ORDER BY total_outstanding_amount DESC;
--===============================================================
-- FUNCTION: Loan Repayment Schedule Generator
-- Returns a month-by-month flat-rate repayment table
---==============================================================

CREATE OR REPLACE FUNCTION generate_loan_schedule(
    p_loan_amount NUMERIC,
    p_interest_rate NUMERIC, -- e.g. 0.20 for 20%
    p_months INT,
    p_start_date DATE
)
RETURNS TABLE (
    month_no INT,
    payment_date DATE,
    opening_balance NUMERIC,
    principal NUMERIC,
    interest NUMERIC,
    installment NUMERIC,
    closing_balance NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        gs AS month_no,
        (p_start_date + (gs || ' month')::interval)::DATE AS payment_date,

        ROUND(p_loan_amount - (p_loan_amount / p_months) * (gs - 1), 2) AS opening_balance,

        ROUND(p_loan_amount / p_months, 2) AS principal,

        ROUND((p_loan_amount * p_interest_rate) / p_months, 2) AS interest,

        ROUND(
            (p_loan_amount / p_months)
            + ((p_loan_amount * p_interest_rate) / p_months),
        2) AS installment,

        ROUND(p_loan_amount - (p_loan_amount / p_months) * gs, 2) AS closing_balance

    FROM generate_series(1, p_months) gs;
END;
$$;
--===============================================================
-- LOAN STATUS UPADATE
--===============================================================
CREATE OR REPLACE FUNCTION update_loan_status()
RETURNS TRIGGER AS $$
DECLARE
    remaining NUMERIC;
BEGIN
    SELECT (l.approved_amount - COALESCE(SUM(p.amount_paid), 0))
    INTO remaining
    FROM Loan l
    LEFT JOIN Payment p ON l.loan_id = p.loan_id
    WHERE l.loan_id = NEW.loan_id
    GROUP BY l.approved_amount;

    IF remaining <= 0 THEN
        UPDATE Loan
        SET status_loan = 'Closed'
        WHERE loan_id = NEW.loan_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- CREATE TRIGGER fraud_trigger
-- AFTER INSERT ON Transaction
-- FOR EACH ROW
-- EXECUTE FUNCTION detect_fraud();

CREATE TRIGGER loan_payment_trigger
AFTER INSERT ON Payment
FOR EACH ROW
EXECUTE FUNCTION update_loan_status();
-- DROP TRIGGER IF EXISTS loan_payment_trigger ON Payment;
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
SELECT trigger_name, event_object_table, action_timing, event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'public';
-- ============================================================
-- TEST DATA: Agricultural Credit & Financial Management System
-- CS232 Semester Project
--
-- HOW TO USE:
--   1. Run your schema file first (agricultural_credit_system_fixed.sql)
--   2. Run this file
--   3. Run the verification queries at the bottom
--
-- WHAT THIS COVERS:
--   - All 11 tables get data
--   - Fraud trigger is tested (one transaction intentionally large)
--   - Loan auto-close trigger is tested
--   - Risk assessment view produces all 4 risk levels
--   - Invoice aging view produces all aging brackets
--   - Outstanding balance report shows correct totals
-- ============================================================

-- ============================================================
-- VERIFICATION QUERIES
-- Run each one and check the expected output described in comments
-- ============================================================
-- ============================================================
-- TEST DATA: Agricultural Credit & Financial Management System
-- CS232 Semester Project
--
-- UUID RULES (why previous file errored):
--   Format:  8-4-4-4-12 hex digits only (0-9, a-f)
--   Invalid: 'app...' has 'p', 'ln...' has 'l' and 'n'
--   Fixed:   'ab...' (a,b both valid hex), 'b0...' (b,0 both valid hex)
--
-- ID LEGEND (easy to remember):
--   Banks       : 11111111... / 22222222... / 33333333...
--   Users       : aaaa1111... / aaaa2222... / aaaa3333...
--   Farmers     : fa000001... / fa000002... / fa000003... / fa000004...
--   Applications: ab000001... / ab000002... / ab000003... / ab000004...
--   Loans       : b0000001... / b0000002... / b0000003...
-- ============================================================


-- ============================================================
-- 1. BANKS
-- ============================================================

INSERT INTO Banks (bank_id, bank_name, headquarters_address, branch_id, contact_number) VALUES
    ('11111111-1111-7111-8111-111111111111', 'Zarai Taraqiati Bank Limited', 'Blue Area, Islamabad',     'ZTBL-001', '051-9252131'),
    ('22222222-2222-7222-8222-222222222222', 'National Bank of Pakistan',    'I.I. Chundrigar, Karachi', 'NBP-001',  '021-99220100'),
    ('33333333-3333-7333-8333-333333333333', 'Bank of Khyber',               'Peshawar Cantt, KPK',      'BOK-001',  '091-9213601');


-- ============================================================
-- 2. USER ACCOUNTS
-- ============================================================

INSERT INTO UserAccounts (user_id, bank_id, username, role, password_hash) VALUES
    ('aaaa1111-aaaa-7aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-7111-8111-111111111111',
     'admin_ztbl',   'Admin',          '$2b$12$examplehashforadminzaaaaaaaaaaaaaaaaaaaaaa'),
    ('aaaa2222-aaaa-7aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-7111-8111-111111111111',
     'officer_ztbl', 'Loan Officer',   '$2b$12$examplehashforofficerzaaaaaaaaaaaaaaaaaaa'),
    ('aaaa3333-aaaa-7aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-7222-8222-222222222222',
     'analyst_nbp',  'Credit Analyst', '$2b$12$examplehashforanalystnaaaaaaaaaaaaaaaaaaa');


-- ============================================================
-- 3. FARMERS
-- ============================================================

INSERT INTO Farmer (farmer_id, name, cnic, phone, address, eligibility, credit_history) VALUES
    ('fa000001-0000-7000-8000-000000000001',
     'Ahmad Nawaz',   '3520212345671', '0300-1111111',
     'Village Topi, District Swabi, KPK',         TRUE,  TRUE),

    ('fa000002-0000-7000-8000-000000000002',
     'Bibi Zainab',   '3520298765432', '0301-2222222',
     'Village Lundkwar, District Swabi, KPK',     TRUE,  TRUE),

    ('fa000003-0000-7000-8000-000000000003',
     'Gul Muhammad',  '3520211111111', '0302-3333333',
     'Village Yar Hussain, District Swabi, KPK',  TRUE,  FALSE),

    ('fa000004-0000-7000-8000-000000000004',
     'Rukhsana Bibi', '3520222222222', '0303-4444444',
     'Village Kalu Khan, District Swabi, KPK',    FALSE, FALSE);


-- ============================================================
-- 4. FARMER FINANCE
-- ============================================================

INSERT INTO farmer_finance (
    farmer_id, reported_date,
    annual_revenue, operating_expenses, net_income,
    total_assets,   cash_on_hand,
    current_assets, current_liabilities,
    total_debt,     annual_debt_service
) VALUES
    -- Farmer A: EBITDA=0.625→1, ROA=0.10→3, CR=1.67→1, DSCR=2.5→1
    ('fa000001-0000-7000-8000-000000000001', '2024-12-01',
     800000, 300000, 200000, 2000000, 150000, 500000, 300000, 400000, 200000),

    -- Farmer B: EBITDA=0.35→2, ROA=0.114→3, CR=1.11→2, DSCR=1.17→3
    ('fa000002-0000-7000-8000-000000000002', '2024-11-15',
     400000, 260000, 80000,  700000,  50000,  200000, 180000, 300000, 120000),

    -- Farmer C: EBITDA=0.12→3, ROA=0.03→4, CR=0.92→3, DSCR=0.857→4
    ('fa000003-0000-7000-8000-000000000003', '2024-10-01',
     250000, 220000, 15000,  500000,  10000,  120000, 130000, 350000, 35000),

    -- Farmer D: EBITDA=0.028→4, ROA=0.0125→4, CR=0.53→4, DSCR=0.083→4
    ('fa000004-0000-7000-8000-000000000004', '2024-09-01',
     180000, 175000, 5000,   400000,  5000,   80000,  150000, 300000, 60000);


-- ============================================================
-- 5. RISK SCORES
-- ============================================================

INSERT INTO RiskScore (farmer_id, sector_risk_value, governance_value, is_in_arrears, calculated_date, remarks) VALUES

    ('fa000001-0000-7000-8000-000000000001',
     8.5, 9.0, FALSE, '2024-12-05', 'Wheat farmer, stable market, good record keeping'),

    ('fa000002-0000-7000-8000-000000000002',
     6.0, 6.5, FALSE, '2024-11-20', 'Sugarcane, moderate price volatility'),

    ('fa000003-0000-7000-8000-000000000003',
     4.0, 3.5, FALSE, '2024-10-10', 'Mixed crops, weak governance practices'),

    ('fa000004-0000-7000-8000-000000000004',
     2.0, 1.5, TRUE,  '2024-09-10', 'Defaulted on prior loan, poor documentation'),

    -- OLD record for Farmer A — DISTINCT ON test.
    -- View must return only the 2024-12-05 record above, not this one.
    ('fa000001-0000-7000-8000-000000000001',
     3.0, 2.0, TRUE,  '2023-01-01', 'OLD RECORD — must be ignored by view (DISTINCT ON test)');


-- ============================================================
-- 6. LOAN APPLICATIONS
-- FIX: 'app' contains 'p' (not hex). Replaced with 'ab' (both valid hex).
-- ============================================================

INSERT INTO LoanApplication (application_id, farmer_id, requested_amount, purpose, application_date, status_application) VALUES

    ('ab000001-0000-7000-8000-000000000001',
     'fa000001-0000-7000-8000-000000000001',
     500000, 'Purchase of wheat seeds and fertilizer',          '2025-01-10', 'Approved'),

    ('ab000002-0000-7000-8000-000000000002',
     'fa000002-0000-7000-8000-000000000002',
     300000, 'Irrigation pipe installation and pump upgrade',   '2025-01-15', 'Approved'),

    ('ab000003-0000-7000-8000-000000000003',
     'fa000003-0000-7000-8000-000000000003',
     200000, 'Land preparation and pesticide purchase',         '2025-02-01', 'Approved'),

    ('ab000004-0000-7000-8000-000000000004',
     'fa000004-0000-7000-8000-000000000004',
     150000, 'General farming expenses',                        '2025-02-10', 'Pending');


-- ============================================================
-- 7. LOANS
-- FIX: 'ln' contains 'l' and 'n' (not hex). Replaced with 'b0' (both valid hex).
-- ============================================================

INSERT INTO Loan (loan_id, application_id, bank_id, approved_amount, interest_rate, start_date, end_date, status_loan) VALUES

    ('b0000001-0000-7000-8000-000000000001',
     'ab000001-0000-7000-8000-000000000001',
     '11111111-1111-7111-8111-111111111111',
     500000, 0.14, '2025-02-01', '2026-02-01', 'Active'),

    ('b0000002-0000-7000-8000-000000000002',
     'ab000002-0000-7000-8000-000000000002',
     '11111111-1111-7111-8111-111111111111',
     300000, 0.14, '2025-02-15', '2026-02-15', 'Active'),

    -- Farmer C: full payment below will trigger auto-close → status becomes 'Closed'
    ('b0000003-0000-7000-8000-000000000003',
     'ab000003-0000-7000-8000-000000000003',
     '22222222-2222-7222-8222-222222222222',
     200000, 0.16, '2025-03-01', '2026-03-01', 'Active');


-- ============================================================
-- 8. COLLATERAL
-- ============================================================

INSERT INTO Collateral (farmer_id, loan_id, land_value, land_type, claim_collateral) VALUES

    ('fa000001-0000-7000-8000-000000000001',
     'b0000001-0000-7000-8000-000000000001',
     1200000, 'Irrigated',     'Non-Claimed'),

    ('fa000002-0000-7000-8000-000000000002',
     'b0000002-0000-7000-8000-000000000002',
     750000,  'Irrigated',     'Non-Claimed'),

    ('fa000003-0000-7000-8000-000000000003',
     'b0000003-0000-7000-8000-000000000003',
     500000,  'Non-Irrigated', 'Non-Claimed');


-- ============================================================
-- 9. PAYMENTS
-- ============================================================

INSERT INTO Payment (loan_id, amount_paid, payment_date, payment_method) VALUES
    ('b0000001-0000-7000-8000-000000000001', 50000,  '2025-03-01', 'Cash'),
    ('b0000001-0000-7000-8000-000000000001', 50000,  '2025-04-01', 'Online');

INSERT INTO Payment (loan_id, amount_paid, payment_date, payment_method) VALUES
    ('b0000002-0000-7000-8000-000000000002', 30000,  '2025-03-15', 'Cash');

-- Full repayment for Farmer C → triggers update_loan_status() → loan closes automatically
INSERT INTO Payment (loan_id, amount_paid, payment_date, payment_method) VALUES
    ('b0000003-0000-7000-8000-000000000003', 200000, '2025-04-01', 'Online');


-- ============================================================
-- 10. TRANSACTIONS  (fraud trigger test)
--
-- Farmer A inserts 3 transactions:
--   tx1: 50,000  (baseline)
--   tx2: 50,000  (average now = 50,000)
--   tx3: 300,000 → 6x average → FRAUD TRIGGER FIRES
--      → auto-inserts row into FraudAlert
--      → sets Farmer.fraud_alert = TRUE
-- ============================================================

INSERT INTO Transaction (farmer_id, loan_id, transaction_type, amount, transaction_date, status_trans) VALUES
    ('fa000001-0000-7000-8000-000000000001',
     'b0000001-0000-7000-8000-000000000001',
     'Loan', 50000, '2025-02-05', 'Completed'),

    ('fa000001-0000-7000-8000-000000000001',
     'b0000001-0000-7000-8000-000000000001',
     'Payment', 50000, '2025-03-01', 'Completed'),

    -- This one triggers fraud detection
    ('fa000001-0000-7000-8000-000000000001',
     'b0000001-0000-7000-8000-000000000001',
     'Loan', 300000, '2025-04-15', 'Pending');

INSERT INTO Transaction (farmer_id, loan_id, transaction_type, amount, transaction_date, status_trans) VALUES
    ('fa000002-0000-7000-8000-000000000002',
     'b0000002-0000-7000-8000-000000000002',
     'Loan', 300000, '2025-02-20', 'Completed'),

    ('fa000002-0000-7000-8000-000000000002',
     'b0000002-0000-7000-8000-000000000002',
     'Payment', 30000, '2025-03-15', 'Completed');

INSERT INTO Transaction (farmer_id, loan_id, transaction_type, amount, transaction_date, status_trans) VALUES
    ('fa000003-0000-7000-8000-000000000003',
     'b0000003-0000-7000-8000-000000000003',
     'Loan', 200000, '2025-03-05', 'Completed');


-- ============================================================
-- 11. INVOICES
-- ============================================================

INSERT INTO Invoice (invoice_no, farmer_id, loan_id, payment_id, amount, issue_date, due_date, status_invoice) VALUES

    ('INV-2025-001',
     'fa000001-0000-7000-8000-000000000001',
     'b0000001-0000-7000-8000-000000000001',
     NULL, 50000, '2025-03-01', '2025-03-31', 'Paid'),

    ('INV-2025-002',
     'fa000002-0000-7000-8000-000000000002',
     'b0000002-0000-7000-8000-000000000002',
     NULL, 30000, '2025-04-01', '2026-01-15', 'Overdue'),

    ('INV-2025-003',
     'fa000001-0000-7000-8000-000000000001',
     'b0000001-0000-7000-8000-000000000001',
     NULL, 50000, '2025-03-01', '2026-04-05', 'Overdue'),

    ('INV-2025-004',
     'fa000002-0000-7000-8000-000000000002',
     'b0000002-0000-7000-8000-000000000002',
     NULL, 30000, '2025-02-01', '2026-03-01', 'Overdue'),

    ('INV-2025-005',
     'fa000003-0000-7000-8000-000000000003',
     'b0000003-0000-7000-8000-000000000003',
     NULL, 40000, '2024-12-01', '2026-02-01', 'Overdue'),

    ('INV-2025-006',
     'fa000004-0000-7000-8000-000000000004',
     NULL, NULL,
     80000, '2024-06-01', '2024-09-01', 'Overdue');


-- ============================================================
-- VERIFICATION QUERIES — run after inserting data
-- ============================================================

-- TEST 1: Risk view — expect 4 rows, one per risk level
SELECT f.name, r.financial_profile_score, r.business_profile_score,
       r.overall_risk_score, r.risk_level
FROM risk_assessment_mof r
JOIN LoanApplication la ON r.application_id = la.application_id
JOIN Farmer f ON la.farmer_id = f.farmer_id
ORDER BY r.overall_risk_score;

-- TEST 2: Fraud trigger fired — expect 1 row for Ahmad Nawaz's 300k transaction
SELECT fa.reason, fa.status_fraud, f.name, t.amount AS flagged_amount
FROM FraudAlert fa
JOIN Transaction t  ON fa.transaction_id = t.transaction_id
JOIN Farmer f       ON t.farmer_id = f.farmer_id;

-- Also verify fraud_alert flag was set on the Farmer row
SELECT name, fraud_alert FROM Farmer WHERE farmer_id = 'fa000001-0000-7000-8000-000000000001';

-- TEST 3: Auto-close — Farmer C's loan should be 'Closed', others 'Active'
SELECT f.name, l.approved_amount, l.status_loan
FROM Loan l
JOIN LoanApplication la ON l.application_id = la.application_id
JOIN Farmer f ON la.farmer_id = f.farmer_id
ORDER BY f.name;

-- TEST 4: Aging brackets — expect all 6 brackets represented
SELECT farmer_name, invoice_no, days_overdue, aging_bracket
FROM invoice_aging_analysis;

-- TEST 5: Outstanding balances
SELECT farmer_name, total_overdue_invoices, total_outstanding_amount, max_days_overdue
FROM outstanding_balance_report;

-- TEST 6: Loan schedule for Farmer A (12 monthly rows, closing_balance row 12 = 0)
SELECT * FROM generate_loan_schedule(500000, 0.14, 12, '2025-02-01'::DATE);
SELECT * FROM RiskScore;