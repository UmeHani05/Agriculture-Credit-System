--commands From this website
-- https://www.postgresql.org/docs/current/sql-commands.html
--enums are used for fixed "option" style inputs
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

CREATE OR REPLACE FUNCTION gen_uuidv7(p_timestamp timestamptz)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
	v_time   numeric;
	v_unix_t numeric;
	v_rand_a numeric;
	v_rand_b numeric;

	v_unix_t_hex varchar;
	v_rand_a_hex varchar;
	v_rand_b_hex varchar;

	v_output_bytes bytea;

	c_milli_factor numeric := 10^3;
	c_micro_factor numeric := 10^6;
	c_scale_factor numeric := 4.096;

	c_version bit(64) := x'0000000000007000';
	c_variant bit(64) := x'8000000000000000';
BEGIN
	v_time := extract(epoch from p_timestamp);

	v_unix_t := trunc(v_time * c_milli_factor);
	v_rand_a := ((v_time * c_micro_factor) - (v_unix_t * c_milli_factor)) * c_scale_factor;
	v_rand_b := random()::numeric * 2^62;

	v_unix_t_hex := lpad(to_hex(v_unix_t::bigint), 12, '0');
	v_rand_a_hex := lpad(to_hex((v_rand_a::bigint::bit(64) | c_version)::bigint), 4, '0');
	v_rand_b_hex := lpad(to_hex((v_rand_b::bigint::bit(64) | c_variant)::bigint), 16, '0');

	v_output_bytes := decode(v_unix_t_hex || v_rand_a_hex || v_rand_b_hex, 'hex');

	RETURN encode(v_output_bytes, 'hex')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION gen_uuidv7()
RETURNS uuid
LANGUAGE plpgsql
AS $$
BEGIN
	RETURN gen_uuidv7(clock_timestamp());
END;
$$;

CREATE TYPE app_status  AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE loan_status          AS ENUM ('Active', 'Closed');
CREATE TYPE payment_method       AS ENUM ('Cash', 'Online');
CREATE TYPE trans_type     AS ENUM ('Loan', 'Payment');
CREATE TYPE trans_status   AS ENUM ('Completed', 'Pending');
CREATE TYPE user_role            AS ENUM ('Admin', 'Loan Officer','Credit Analyst');
CREATE TYPE invoice_status       AS ENUM ('Paid', 'Overdue');
--changed from "Detected" to "Pending" kyunke fraud alert ke liye pending zyada sahi lagta hai, aur verified/dismissed uske baad aayenge
CREATE TYPE fraud_status AS ENUM ('Pending', 'Verified', 'Dismissed'); 


CREATE TABLE Banks(--Centralized banking as we need to keep track of the banks and their relationship with the farmers and the loans.
    bank_id UUID PRIMARY KEY DEFAULT gen_uuidv7(),
    bank_name VARCHAR(150) NOT NULL UNIQUE,
    headquarters_address VARCHAR(255),
    branch_id VARCHAR(50) NOT NULL UNIQUE,
    contact_number VARCHAR(20)
);
--changed the name from User to UserAccounts 
CREATE TABLE UserAccounts (
   user_id       UUID PRIMARY KEY DEFAULT gen_uuidv7(),--as for security and scalability
   bank_id       UUID            NOT NULL REFERENCES Banks(bank_id) ON DELETE CASCADE,
--    bank_name          VARCHAR(150)    NOT NULL REFERENCES Banks(bank_name),--this should be imported from Banks-not sure
   bank_name          VARCHAR(150)    NOT NULL, --this should be imported from Banks
   username TEXT            NOT NULL UNIQUE,
    role               user_role       NOT NULL,
   password_hash      TEXT            NOT NULL--hash value stored with password hashing algorithm and with salt
);

CREATE TABLE Farmer (
    farmer_id        UUID PRIMARY KEY DEFAULT gen_uuidv7(),--as for security and scalability
    name              VARCHAR(150)    NOT NULL,
    cnic              VARCHAR(15)     NOT NULL UNIQUE, 
    phone             VARCHAR(20),
    address           TEXT,
    registration_date DATE            NOT NULL DEFAULT CURRENT_DATE,
	Land 			FLOAT(1),
	Credit_History  BOOL,
	Guarantors      VARCHAR(150),
	Eligibility		BOOL
	--removed the fraud alert column from farmer table because it can be determined from the transactions and fraud alert tables, and it would be redundant to keep it in the farmer table. Instead, we can calculate the fraud alert status for a farmer based on their transactions and any associated fraud alerts.		
);

-- i added this table to keep track of the land details of the farmers, which can be useful for loan eligibility and risk assessment. It has a foreign key reference to the Farmer table, so if a farmer is deleted, their land records will also be deleted (ON DELETE CASCADE).
--we can check this later
CREATE TABLE Land (
    land_id SERIAL PRIMARY KEY,
    farmer_id UUID REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    area NUMERIC(10,2),
    location TEXT,
    soil_type TEXT
);
--idk how to incorporate this into the bank thingy

CREATE TABLE RiskScore (
    risk_id          SERIAL          PRIMARY KEY,
    farmer_id        UUID             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,  --delete kyunke faida nahi isse rakhne ka
    score_value      NUMERIC(5, 2)   NOT NULL,  
    calculated_date  DATE            NOT NULL DEFAULT CURRENT_DATE,
    remarks          TEXT
	);
 
CREATE TABLE LoanApplication (
    application_id     UUID PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id         UUID                 NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    requested_amount  NUMERIC(15, 2)      NOT NULL,
    purpose           TEXT,
    --here too
    risk_score        NUMERIC(5, 2),                   
    application_date  DATE                NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,--added timestamp as importnat feature 
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status_application            app_status  NOT NULL DEFAULT 'Pending' --naya seekha hai values dalne ke baad hi pata chalega
);
--loan table
CREATE TABLE Loan (
    loan_id          UUID PRIMARY KEY DEFAULT gen_uuidv7(),
    application_id   UUID           NOT NULL UNIQUE REFERENCES LoanApplication(application_id) ON DELETE RESTRICT,
    approved_amount  NUMERIC(15, 2) NOT NULL,
    interest_rate    NUMERIC(5, 2)  NOT NULL,   --again not sure if we are going with interest
    start_date       DATE          NOT NULL,
    end_date         DATE          NOT NULL,
    status_loan           loan_status   NOT NULL DEFAULT 'Active',
    CONSTRAINT chk_loan_dates CHECK (end_date > start_date)
);

-- Loan Repayment Schedule Generator
-- repayment schedule guys 

CREATE TABLE LoanSchedule (
    schedule_id SERIAL PRIMARY KEY,
    loan_id UUID REFERENCES Loan(loan_id) ON DELETE CASCADE,
    month_no INT,
    payment_date DATE,
    principal NUMERIC(15,2),
    interest NUMERIC(15,2),
    installment NUMERIC(15,2),
    closing_balance NUMERIC(15,2)
);

--also like a lot of dependent "references" thingy so might have a few errors
CREATE TABLE Payment (
    payment_id      SERIAL          PRIMARY KEY,
    loan_id         UUID             NOT NULL REFERENCES Loan(loan_id) ON DELETE RESTRICT,
    amount_paid     NUMERIC(15, 2)  NOT NULL CHECK (amount_paid > 0),
    payment_date    DATE            NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    payment_method  payment_method  NOT NULL
);

-- !! Batana payment alag hai from transaction

--changed name from Transaction to Transactions because of error (reserved word hai)--
CREATE TABLE Transactions (
    transaction_id  SERIAL              PRIMARY KEY,
    farmer_id       UUID                 NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    type            trans_type    NOT NULL, --enum use kiya hai and type kyunke mujhe kuch aur nahi yaad
    amount          NUMERIC(15, 2)      NOT NULL CHECK (amount > 0),
    date            DATE                NOT NULL DEFAULT CURRENT_DATE,
    transferred_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status_trans          trans_status  NOT NULL DEFAULT 'Pending'
);
--Fraud Table
CREATE TABLE FraudAlert (
    alert_id        SERIAL             PRIMARY KEY,
    transaction_id  INT                NOT NULL REFERENCES Transactions(transaction_id) ON DELETE CASCADE,
    reason          TEXT               NOT NULL,
    flag_date       DATE               NOT NULL DEFAULT CURRENT_DATE,
    status          fraud_status NOT NULL DEFAULT 'Pending'
);
--Invoice Table
CREATE TABLE Invoice (
    invoice_id   SERIAL          PRIMARY KEY,
    invoice_no   VARCHAR(50)     NOT NULL UNIQUE,
    farmer_id    UUID             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    amount       NUMERIC(15, 2)  NOT NULL CHECK (amount > 0),
    issue_date   DATE            NOT NULL DEFAULT CURRENT_DATE,
    due_date     DATE            NOT NULL,
    status_invoice       invoice_status  NOT NULL DEFAULT 'Overdue',
    CONSTRAINT chk_invoice_dates CHECK (due_date >= issue_date)
);


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

--also according to geeksforgeeks we can incorporate indexes sir ne aaj parhaya hai

CREATE OR REPLACE FUNCTION detect_fraud()
RETURNS TRIGGER AS $$
DECLARE
    avg_amount NUMERIC;
BEGIN
    SELECT COALESCE(AVG(amount), 0)
    INTO avg_amount
    FROM Transactions
    WHERE farmer_id = NEW.farmer_id;

    IF NEW.amount > GREATEST(avg_amount * 2, 30000) THEN
        INSERT INTO FraudAlert (transaction_id, reason, status)
        VALUES (NEW.transaction_id, 'Suspicious transaction detected', 'Pending');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER fraud_trigger
AFTER INSERT ON Transactions
FOR EACH ROW
EXECUTE FUNCTION detect_fraud();
