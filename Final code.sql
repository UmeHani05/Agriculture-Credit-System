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
CREATE TYPE trans_type       AS ENUM ('Loan', 'Payment');
CREATE TYPE trans_status     AS ENUM ('Completed', 'Pending');
CREATE TYPE user_role        AS ENUM ('Bank Manager', 'Loan Officer', 'Credit Analyst');
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
    branch_id            VARCHAR(50)  NOT NULL UNIQUE,
    contact_number       VARCHAR(20)
);

CREATE TABLE UserAccounts (
    user_id       UUID      PRIMARY KEY DEFAULT gen_uuidv7(),
    bank_id       UUID      NOT NULL REFERENCES Banks(bank_id) ON DELETE CASCADE,
    username      TEXT      NOT NULL UNIQUE,
    role          user_role NOT NULL,
    password_hash TEXT      NOT NULL
);

CREATE TABLE Farmer (
    farmer_id         UUID         PRIMARY KEY DEFAULT gen_uuidv7(),
    name              VARCHAR(150) NOT NULL,
    cnic              VARCHAR(15)  NOT NULL UNIQUE,
    phone             VARCHAR(20),
    address           TEXT,
    registration_date DATE         NOT NULL DEFAULT CURRENT_DATE,
    eligibility       BOOLEAN,
    fraud_alert       BOOLEAN      NOT NULL DEFAULT FALSE,
    credit_history    BOOLEAN
);

CREATE TABLE farmer_finance (
    farmer_finance_id   UUID      PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id           UUID          NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    reported_date       DATE          NOT NULL DEFAULT CURRENT_DATE,
    annual_revenue      NUMERIC(15,2),
    operating_expenses  NUMERIC(15,2),
    net_income          NUMERIC(15,2),  -- used in ROA: net_income / total_assets
    total_assets        NUMERIC(15,2),
    cash_on_hand        NUMERIC(15,2),
    current_assets      NUMERIC(15,2),
    current_liabilities NUMERIC(15,2),
    total_debt          NUMERIC(15,2),
    annual_debt_service NUMERIC(15,2),
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
CREATE TABLE FarmerAccount (
    account_id      UUID           PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id       UUID           NOT NULL REFERENCES Farmer(farmer_id),
    bank_id         UUID           NOT NULL REFERENCES Banks(bank_id),
    branch_id      VARCHAR  (50)       REFERENCES Banks(branch_id),
    account_number  VARCHAR(20)    NOT NULL UNIQUE,
    balance         NUMERIC(15,2)  NOT NULL DEFAULT 0,
    is_active       BOOLEAN        NOT NULL DEFAULT TRUE,
    opened_date     DATE           NOT NULL DEFAULT CURRENT_DATE,
    deleted_at      TIMESTAMP,
    created_at      TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- DEPENDENT ENTITIES
-- ============================================================
CREATE TABLE LoanApplication (
    application_id     UUID          PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id          UUID          NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    requested_amount   NUMERIC(15,2) NOT NULL CHECK (requested_amount > 0),
    purpose            TEXT,
    fraud_alert        BOOLEAN       NOT NULL DEFAULT FALSE,
    application_date   DATE          NOT NULL DEFAULT CURRENT_DATE,
    created_at         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_application app_status    NOT NULL DEFAULT 'Pending'
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
    farmer_id      UUID          NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    loan_id        UUID          REFERENCES Loan(loan_id) ON DELETE SET NULL,
    type           trans_type    NOT NULL,
    amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    transaction_date           DATE          NOT NULL DEFAULT CURRENT_DATE,
    transferred_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_trans   trans_status  NOT NULL DEFAULT 'Pending'
);

CREATE TABLE Invoice (
    invoice_id     UUID           PRIMARY KEY DEFAULT gen_uuidv7(),
    invoice_no     VARCHAR(50)    NOT NULL UNIQUE,
    farmer_id      UUID           NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
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
        BEGIN
            INSERT INTO FraudAlert (transaction_id, reason, status_fraud)
            VALUES (NEW.transaction_id, 'Suspicious transaction detected', 'Detected');
            UPDATE Farmer-- this will update the farmer's fraud alert frequently
            SET fraud_alert=TRUE
            WHERE farmer_id=NEW.farmer_id;
        END;
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

        (ff.annual_revenue - ff.operating_expenses) / NULLIF(ff.annual_revenue, 0)      
        AS ebitda_margin,
        ff.net_income / NULLIF(ff.total_assets, 0)                                       
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
    
    JOIN (
        SELECT
            loan_id,
            SUM(land_value) AS land_value   -- aggregate to one row per loan
        FROM Collateral
        GROUP BY loan_id
    ) c ON c.loan_id = (
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
        WHEN overall_risk_score BETWEEN 1.0 AND 1.4 THEN 'Low Risk'
        WHEN overall_risk_score BETWEEN 1.5 AND 2.4 THEN 'Moderate Risk'
        WHEN overall_risk_score BETWEEN 2.5 AND 3.4 THEN 'Elevated Risk'
        ELSE 'High Risk'
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
--======================================================
---End of Schema
---======================================================


--Loan Officer    ->  user_id prefix: LO_
--Credit Analyst ->  user_id prefix: CA_  
--admin to bank manager

ALTER TABLE UserAccounts
    ALTER COLUMN user_id DROP DEFAULT;

ALTER TABLE UserAccounts
    ALTER COLUMN user_id TYPE TEXT
    USING user_id::TEXT;

ALTER TABLE UserAccounts
    DROP CONSTRAINT IF EXISTS chk_user_id_prefix;

ALTER TABLE UserAccounts
    ADD CONSTRAINT chk_user_id_prefix
    CHECK (
        user_id LIKE 'LO_%' OR
        user_id LIKE 'CA_%' OR
        user_id LIKE 'BM_%'
    );

CREATE OR REPLACE FUNCTION fn_generate_prefixed_user_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        NEW.user_id :=
            CASE NEW.role
                WHEN 'Loan Officer'   THEN 'LO_'
                WHEN 'Credit Analyst' THEN 'CA_'
                WHEN 'Bank Manager'   THEN 'BM_'
            END
            || REPLACE(gen_random_uuid()::TEXT, '-', '');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS trg_useraccount_prefix_id ON UserAccounts;

CREATE TRIGGER trg_useraccount_prefix_id
    BEFORE INSERT ON UserAccounts
    FOR EACH ROW EXECUTE FUNCTION fn_generate_prefixed_user_id();


--role based access and security thingy

CREATE ROLE role_loan_officer;
CREATE ROLE role_credit_analyst;
CREATE ROLE role_bank_manager;

--loan off.
GRANT SELECT                                   ON Farmer          TO role_loan_officer;
GRANT SELECT, INSERT                           ON LoanApplication TO role_loan_officer;
--GRANT UPDATE (status_application, updated_at) ON LoanApplication TO role_loan_officer;
GRANT SELECT                                   ON Loan            TO role_loan_officer;
GRANT SELECT                 ON FraudAlert     TO role_loan_officer;

--credit an
GRANT SELECT                 ON Transaction    TO role_credit_analyst;
GRANT SELECT                 ON FraudAlert     TO role_credit_analyst;
GRANT SELECT                 ON RiskScore      TO role_credit_analyst;
GRANT SELECT                 ON Invoice        TO role_credit_analyst;
GRANT SELECT                 ON Payment        TO role_credit_analyst;
GRANT SELECT                 ON Collateral     TO role_credit_analyst;
GRANT SELECT                 ON Loan           TO role_credit_analyst;
GRANT SELECT                 ON Farmer         TO role_credit_analyst;
GRANT SELECT, INSERT, UPDATE ON farmer_finance TO role_credit_analyst;



GRANT SELECT ON risk_assessment_mof        TO role_credit_analyst;
GRANT SELECT ON invoice_aging_analysis     TO role_credit_analyst;
GRANT SELECT ON outstanding_balance_report TO role_credit_analyst;

--changed to bank manager
GRANT SELECT ON FraudAlert TO role_bank_manager;
GRANT SELECT ON LoanApplication TO role_bank_manager;
GRANT UPDATE (status_application, updated_at) ON LoanApplication TO role_bank_manager;
GRANT SELECT ON Loan TO role_bank_manager;

--security (cyber sekorti)
ALTER TABLE LoanApplication ENABLE ROW LEVEL SECURITY;
ALTER TABLE Transaction     ENABLE ROW LEVEL SECURITY;
ALTER TABLE FraudAlert      ENABLE ROW LEVEL SECURITY;
ALTER TABLE farmer_finance  ENABLE ROW LEVEL SECURITY;
ALTER TABLE RiskScore       ENABLE ROW LEVEL SECURITY;
ALTER TABLE Invoice         ENABLE ROW LEVEL SECURITY;

ALTER TABLE LoanApplication FORCE ROW LEVEL SECURITY;
ALTER TABLE Transaction     FORCE ROW LEVEL SECURITY;
ALTER TABLE FraudAlert      FORCE ROW LEVEL SECURITY;
ALTER TABLE farmer_finance  FORCE ROW LEVEL SECURITY;
ALTER TABLE RiskScore       FORCE ROW LEVEL SECURITY;
ALTER TABLE Invoice         FORCE ROW LEVEL SECURITY;

--app. access to only lo
CREATE POLICY pol_loanapp_lo_select ON LoanApplication
    FOR SELECT TO role_loan_officer
    USING (TRUE);

CREATE POLICY pol_loanapp_lo_insert ON LoanApplication
    FOR INSERT TO role_loan_officer
    WITH CHECK (TRUE);

CREATE POLICY pol_fraud_lo_select ON FraudAlert
    FOR SELECT TO role_loan_officer
    USING (TRUE);

--changed to bank manager
CREATE POLICY pol_loanapp_bm_update ON LoanApplication
    FOR UPDATE TO role_bank_manager
    USING  (status_application = 'Pending')
    WITH CHECK (status_application IN ('Approved', 'Rejected'));

CREATE POLICY pol_fraud_bm_select ON FraudAlert
    FOR SELECT TO role_bank_manager
    USING (TRUE);

--analyst only read
CREATE POLICY pol_trans_ca_select ON Transaction
    FOR SELECT TO role_credit_analyst
    USING (TRUE);

CREATE POLICY pol_fraud_ca_select ON FraudAlert
    FOR SELECT TO role_credit_analyst
    USING (TRUE);

CREATE POLICY pol_risk_ca_select ON RiskScore
    FOR SELECT TO role_credit_analyst
    USING (TRUE);

CREATE POLICY pol_invoice_ca_select ON Invoice
    FOR SELECT TO role_credit_analyst
    USING (TRUE);

--analyst access finance stuff
CREATE POLICY pol_ff_ca_all ON farmer_finance
    FOR ALL TO role_credit_analyst
    USING (TRUE)
    WITH CHECK (TRUE);

--ye hum hain jo sab dekhte hain 

CREATE POLICY pol_bank_manager_fraud ON FraudAlert
    FOR ALL TO role_bank_manager USING (TRUE) WITH CHECK (TRUE);

--uhh error araha tha then ai told me shared access bhi hona chahiye so yeah 
CREATE OR REPLACE FUNCTION fn_check_access(
    p_user_id         TEXT,
    p_required_prefix TEXT
)
RETURNS VOID AS $$
DECLARE
    v_role_name TEXT :=
        CASE p_required_prefix
            WHEN 'LO' THEN 'Loan Officer'
            WHEN 'CA' THEN 'Credit Analyst'
            WHEN 'BM' THEN 'Bank Manager'
            ELSE p_required_prefix
        END;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM UserAccounts WHERE user_id = p_user_id) THEN
        RAISE EXCEPTION 'Authentication Failed: user "%" not found.', p_user_id;
    END IF;

    IF LEFT(p_user_id, 2) != p_required_prefix THEN
        RAISE EXCEPTION
            'Authorization Failed: this operation requires % access. '
            'user_id "%" does not carry that role.',
            v_role_name, p_user_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--loan shark ko jo allow hai
CREATE OR REPLACE PROCEDURE lo_submit_application(
    p_user_id   TEXT,
    p_farmer_id UUID,
    p_amount    NUMERIC,
    p_purpose   TEXT DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'LO');

    IF NOT EXISTS (SELECT 1 FROM Farmer WHERE farmer_id = p_farmer_id) THEN
        RAISE EXCEPTION 'Farmer "%" does not exist.', p_farmer_id;
    END IF;

    IF EXISTS (
        SELECT 1 FROM LoanApplication
        WHERE farmer_id          = p_farmer_id
          AND status_application = 'Pending'
    ) THEN
        RAISE EXCEPTION
            'Farmer "%" already has a Pending application. '
            'Resolve it before submitting a new one.', p_farmer_id;
    END IF;

    INSERT INTO LoanApplication (farmer_id, requested_amount, purpose)
    VALUES (p_farmer_id, p_amount, p_purpose);

    RAISE NOTICE 'Application submitted for farmer %.', p_farmer_id;
END;
$$;


CREATE OR REPLACE PROCEDURE bm_update_app_status(
    p_user_id        TEXT,
    p_application_id UUID,
    p_new_status     app_status
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'BM');

    IF p_new_status NOT IN ('Approved', 'Rejected') THEN
        RAISE EXCEPTION
            'Invalid target status "%". Only Approved or Rejected are allowed.',
            p_new_status;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM LoanApplication
        WHERE application_id    = p_application_id
          AND status_application = 'Pending'
    ) THEN
        RAISE EXCEPTION
            'Application "%" not found or is not in Pending status.',
            p_application_id;
    END IF;

    UPDATE LoanApplication
       SET status_application = p_new_status
     WHERE application_id = p_application_id;

    RAISE NOTICE 'Application % updated to %.', p_application_id, p_new_status;
END;
$$;


CREATE OR REPLACE FUNCTION lo_get_applications(p_user_id TEXT)
RETURNS TABLE (
    application_id     UUID,
    farmer_name        VARCHAR(150),
    cnic               VARCHAR(15),
    requested_amount   NUMERIC,
    purpose            TEXT,
    application_date   DATE,
    status_application app_status,
    fraud_alert        BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'LO');

    RETURN QUERY
    SELECT
        la.application_id,
        f.name,
        f.cnic,
        la.requested_amount,
        la.purpose,
        la.application_date,
        la.status_application,
        la.fraud_alert
    FROM LoanApplication la
    JOIN Farmer f ON la.farmer_id = f.farmer_id
    ORDER BY la.application_date DESC;
END;
$$;

--jo ca ko allow hai karna
CREATE OR REPLACE FUNCTION ca_get_transactions(p_user_id TEXT)
RETURNS TABLE (
    transaction_id UUID,
    farmer_name    VARCHAR(150),
    type           trans_type,
    amount         NUMERIC,
    date           DATE,
    status_trans   trans_status
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'CA');

    RETURN QUERY
    SELECT
        t.transaction_id,
        f.name,
        t.type,
        t.amount,
        t.transaction_date,
        t.status_trans
    FROM Transaction t
    JOIN Farmer f ON t.farmer_id = f.farmer_id
    ORDER BY t.transaction_date DESC;
END;
$$;


CREATE OR REPLACE FUNCTION ca_get_fraud_alerts(p_user_id TEXT)
RETURNS TABLE (
    alert_id       UUID,
    transaction_id UUID,
    application_id UUID,
    reason         TEXT,
    flag_date      DATE,
    status_fraud   fraud_status
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'CA');

    RETURN QUERY
    SELECT
        fa.alert_id,
        fa.transaction_id,
        fa.application_id,
        fa.reason,
        fa.flag_date,
        fa.status_fraud
    FROM FraudAlert fa
    ORDER BY fa.flag_date DESC;
END;
$$;


CREATE OR REPLACE FUNCTION ca_get_risk_scores(p_user_id TEXT)
RETURNS TABLE (
    risk_id           UUID,
    farmer_name       VARCHAR(150),
    sector_risk_value NUMERIC,
    governance_value  NUMERIC,
    is_in_arrears     BOOLEAN,
    calculated_date   DATE,
    remarks           TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'CA');

    RETURN QUERY
    SELECT
        rs.risk_id,
        f.name,
        rs.sector_risk_value,
        rs.governance_value,
        rs.is_in_arrears,
        rs.calculated_date,
        rs.remarks
    FROM RiskScore rs
    JOIN Farmer f ON rs.farmer_id = f.farmer_id
    ORDER BY rs.calculated_date DESC;
END;
$$;


CREATE OR REPLACE FUNCTION ca_get_risk_assessment(p_user_id TEXT)
RETURNS TABLE (
    application_id          UUID,
    financial_profile_score NUMERIC,
    business_profile_score  NUMERIC,
    overall_risk_score      NUMERIC,
    risk_level              TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'CA');
    RETURN QUERY SELECT * FROM risk_assessment_mof;
END;
$$;


CREATE OR REPLACE FUNCTION ca_get_invoice_aging(p_user_id TEXT)
RETURNS TABLE (
    farmer_name       VARCHAR(150),
    cnic              VARCHAR(15),
    invoice_no        VARCHAR(50),
    amount            NUMERIC,
    issue_date        DATE,
    due_date          DATE,
    days_since_issued INTEGER,
    days_overdue      INTEGER,
    status_invoice    invoice_status,
    aging_bracket     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'CA');
    RETURN QUERY SELECT * FROM invoice_aging_analysis;
END;
$$;


CREATE OR REPLACE FUNCTION ca_get_outstanding_balances(p_user_id TEXT)
RETURNS TABLE (
    farmer_id                UUID,
    farmer_name              VARCHAR(150),
    cnic                     VARCHAR(15),
    phone                    VARCHAR(20),
    total_overdue_invoices   BIGINT,
    total_outstanding_amount NUMERIC,
    oldest_due_date          DATE,
    max_days_overdue         INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'CA');
    RETURN QUERY SELECT * FROM outstanding_balance_report;
END;
$$;


CREATE OR REPLACE PROCEDURE ca_upsert_farmer_finance(
    p_user_id         TEXT,
    p_farmer_id       UUID,
    p_reported_date   DATE,
    p_annual_revenue  NUMERIC,
    p_op_expenses     NUMERIC,
    p_net_income      NUMERIC,
    p_total_assets    NUMERIC,
    p_cash_on_hand    NUMERIC,
    p_current_assets  NUMERIC,
    p_current_liabs   NUMERIC,
    p_total_debt      NUMERIC,
    p_annual_debt_svc NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'CA');

    IF NOT EXISTS (SELECT 1 FROM Farmer WHERE farmer_id = p_farmer_id) THEN
        RAISE EXCEPTION 'Farmer "%" not found.', p_farmer_id;
    END IF;

    INSERT INTO farmer_finance (
        farmer_id,           reported_date,
        annual_revenue,      operating_expenses, net_income,
        total_assets,        cash_on_hand,       current_assets,
        current_liabilities, total_debt,         annual_debt_service
    )
    VALUES (
        p_farmer_id,         p_reported_date,
        p_annual_revenue,    p_op_expenses,      p_net_income,
        p_total_assets,      p_cash_on_hand,     p_current_assets,
        p_current_liabs,     p_total_debt,       p_annual_debt_svc
    )
    ON CONFLICT ON CONSTRAINT uq_farmer_finance_date DO UPDATE SET
        annual_revenue      = EXCLUDED.annual_revenue,
        operating_expenses  = EXCLUDED.operating_expenses,
        net_income          = EXCLUDED.net_income,
        total_assets        = EXCLUDED.total_assets,
        cash_on_hand        = EXCLUDED.cash_on_hand,
        current_assets      = EXCLUDED.current_assets,
        current_liabilities = EXCLUDED.current_liabilities,
        total_debt          = EXCLUDED.total_debt,
        annual_debt_service = EXCLUDED.annual_debt_service;

    RAISE NOTICE 'Farmer finance record saved for farmer % on %.', p_farmer_id, p_reported_date;
END;
$$;

