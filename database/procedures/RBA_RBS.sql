--Loan Officer    ->  user_id prefix: LO_
--Credit Analyst ->  user_id prefix: CA_  
--Admin           ->  user_id prefix: AD_

ALTER TABLE UserAccounts
    ALTER COLUMN user_id DROP DEFAULT;

ALTER TABLE UserAccounts
    ALTER COLUMN user_id TYPE TEXT
    USING user_id::TEXT;

ALTER TABLE UserAccounts
    ADD CONSTRAINT chk_user_id_prefix
    CHECK (
        user_id LIKE 'LO_%' OR
        user_id LIKE 'CA_%' OR
        user_id LIKE 'AD_%'
    );

CREATE OR REPLACE FUNCTION fn_generate_prefixed_user_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        NEW.user_id :=
            CASE NEW.role
                WHEN 'Loan Officer'   THEN 'LO_'
                WHEN 'Credit Analyst' THEN 'CA_'
                WHEN 'Admin'          THEN 'AD_'
            END
            || REPLACE(gen_random_uuid()::TEXT, '-', '');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_useraccount_prefix_id
    BEFORE INSERT ON UserAccounts
    FOR EACH ROW EXECUTE FUNCTION fn_generate_prefixed_user_id();


--role based access and security thingy

CREATE ROLE role_loan_officer;
CREATE ROLE role_credit_analyst;
CREATE ROLE role_admin;

--loan off.
GRANT SELECT                                   ON Farmer          TO role_loan_officer;
GRANT SELECT, INSERT                           ON LoanApplication TO role_loan_officer;
GRANT UPDATE (status_application, updated_at) ON LoanApplication TO role_loan_officer;
GRANT SELECT                                   ON Loan            TO role_loan_officer;

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

GRANT USAGE ON SEQUENCE farmer_finance_farmer_finance_id_seq TO role_credit_analyst;

GRANT SELECT ON risk_assessment_mof        TO role_credit_analyst;
GRANT SELECT ON invoice_aging_analysis     TO role_credit_analyst;
GRANT SELECT ON outstanding_balance_report TO role_credit_analyst;

--admin (could be bank idk)
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO role_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO role_admin;

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

CREATE POLICY pol_loanapp_lo_update ON LoanApplication
    FOR UPDATE TO role_loan_officer
    USING  (status_application = 'Pending')
    WITH CHECK (status_application IN ('Approved', 'Rejected'));

--analyst only read
CREATE POLICY pol_trans_fa_select ON Transaction
    FOR SELECT TO role_credit_analyst
    USING (TRUE);

CREATE POLICY pol_fraud_fa_select ON FraudAlert
    FOR SELECT TO role_credit_analyst
    USING (TRUE);

CREATE POLICY pol_risk_fa_select ON RiskScore
    FOR SELECT TO role_credit_analyst
    USING (TRUE);

CREATE POLICY pol_invoice_fa_select ON Invoice
    FOR SELECT TO role_credit_analyst
    USING (TRUE);

--analyst access finance stuff
CREATE POLICY pol_ff_fa_all ON farmer_finance
    FOR ALL TO role_credit_analyst
    USING (TRUE)
    WITH CHECK (TRUE);

--ye hum hain jo sab dekhte hain 
CREATE POLICY pol_admin_loanapp ON LoanApplication
    FOR ALL TO role_admin USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY pol_admin_trans ON Transaction
    FOR ALL TO role_admin USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY pol_admin_fraud ON FraudAlert
    FOR ALL TO role_admin USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY pol_admin_ff ON farmer_finance
    FOR ALL TO role_admin USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY pol_admin_risk ON RiskScore
    FOR ALL TO role_admin USING (TRUE) WITH CHECK (TRUE);

CREATE POLICY pol_admin_invoice ON Invoice
    FOR ALL TO role_admin USING (TRUE) WITH CHECK (TRUE);

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
            WHEN 'AD' THEN 'Admin'
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


CREATE OR REPLACE PROCEDURE lo_update_app_status(
    p_user_id        TEXT,
    p_application_id UUID,
    p_new_status     app_status
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM fn_check_access(p_user_id, 'LO');

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
        t.date,
        t.status_trans
    FROM Transaction t
    JOIN Farmer f ON t.farmer_id = f.farmer_id
    ORDER BY t.date DESC;
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
    risk_id           INT,
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

