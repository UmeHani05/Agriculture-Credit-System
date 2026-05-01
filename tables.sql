--commands yahan se chori kiya hai
--https://www.postgresql.org/docs/current/sql-commands.html
--gang syntax ka issue hosakta hai please comments karke batadena

--enums are used for fixed "option" style inputs
CREATE TYPE app_status       AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE loan_status      AS ENUM ('Active', 'Closed');
CREATE TYPE payment_method   AS ENUM ('Cash', 'Online');
CREATE TYPE trans_type       AS ENUM ('Loan', 'Payment');
CREATE TYPE trans_status     AS ENUM ('Completed', 'Pending');
CREATE TYPE user_role        AS ENUM ('Admin', 'Loan Officer', 'Credit Analyst');
CREATE TYPE invoice_status   AS ENUM ('Paid', 'Overdue');
CREATE TYPE fraud_status     AS ENUM ('Detected', 'Undetected');
CREATE TYPE land_type        AS ENUM ('Irrigated', 'Non-Irrigated', 'Pasture');
CREATE TYPE claim_collateral AS ENUM ('Claimed', 'Non-Claimed', 'Partially Claimed');

--independent entities
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE Banks (
    bank_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bank_name VARCHAR(150) NOT NULL UNIQUE,
    headquarters_address VARCHAR(255),
    branch_id VARCHAR(50) NOT NULL UNIQUE,
    contact_number VARCHAR(20)
);

CREATE TABLE UserAccounts (
    user_id       UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    bank_id       UUID      NOT NULL REFERENCES Banks(bank_id) ON DELETE CASCADE,
    username      TEXT      NOT NULL UNIQUE,
    role          user_role NOT NULL,
    password_hash TEXT      NOT NULL 
);

CREATE TABLE Farmer (
    farmer_id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name              VARCHAR(150) NOT NULL,
    cnic              VARCHAR(15)  NOT NULL UNIQUE,
    phone             VARCHAR(20),
    address           TEXT,
    registration_date DATE         NOT NULL DEFAULT CURRENT_DATE,
    eligibility       BOOLEAN,      
    fraud_alert       BOOLEAN,      
    credit_history    BOOLEAN       
);

--please tell me again agar iski entity thi ya sirf calculation ka kaam tha
CREATE TABLE RiskScore (
    risk_id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id       UUID         NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    score_value     NUMERIC(5,2) NOT NULL CHECK (score_value BETWEEN 0 AND 100),
    calculated_date DATE         NOT NULL DEFAULT CURRENT_DATE,
    remarks         TEXT
);

CREATE TABLE LoanApplication (
    application_id   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id        UUID         NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    requested_amount NUMERIC(15,2) NOT NULL CHECK (requested_amount > 0),
    purpose          TEXT,
    fraud_alert      BOOLEAN      NOT NULL DEFAULT FALSE,
    risk_score       NUMERIC(5,2), 
    application_date DATE         NOT NULL DEFAULT CURRENT_DATE,
    created_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_application app_status NOT NULL DEFAULT 'Pending'
);

--dependent entities
CREATE TABLE Loan (
    loan_id         UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id  UUID          NOT NULL UNIQUE REFERENCES LoanApplication(application_id) ON DELETE RESTRICT,
    bank_id         UUID          NOT NULL REFERENCES Banks(bank_id) ON DELETE RESTRICT,
    approved_amount NUMERIC(15,2) NOT NULL CHECK (approved_amount > 0),
    interest_rate   NUMERIC(5,2)  NOT NULL CHECK (interest_rate >= 0),
    start_date      DATE          NOT NULL,
    end_date        DATE          NOT NULL,
    status_loan     loan_status   NOT NULL DEFAULT 'Active',
    CONSTRAINT chk_loan_dates CHECK (end_date > start_date)
);


--idhr guarantor hat gaya sirf collateral hai.

CREATE TABLE Collateral (
    collateral_id    UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id        UUID             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    loan_id          UUID             NOT NULL REFERENCES Loan(loan_id) ON DELETE CASCADE,
    land_value       NUMERIC(15,2)    NOT NULL CHECK (land_value > 0),
    land_type        land_type        NOT NULL,
    claim_collateral claim_collateral NOT NULL DEFAULT 'Non-Claimed'
);

CREATE TABLE Payment (
    payment_id     UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    loan_id        UUID           NOT NULL REFERENCES Loan(loan_id) ON DELETE RESTRICT,
    amount_paid    NUMERIC(15,2)  NOT NULL CHECK (amount_paid > 0),
    payment_date   DATE           NOT NULL DEFAULT CURRENT_DATE,
    payment_method payment_method NOT NULL,
    created_at     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);


--this is for da report i think kaam ki cheez hai gen1
CREATE TABLE Transaction (
    transaction_id UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    farmer_id      UUID          NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    type           trans_type    NOT NULL,
    amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    date           DATE          NOT NULL DEFAULT CURRENT_DATE,
    transferred_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status_trans   trans_status  NOT NULL DEFAULT 'Pending'
);

CREATE TABLE Invoice (
    invoice_id     UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_no     VARCHAR(50)    NOT NULL UNIQUE,
    farmer_id      UUID           NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    amount         NUMERIC(15,2)  NOT NULL CHECK (amount > 0),
    issue_date     DATE           NOT NULL DEFAULT CURRENT_DATE,
    due_date       DATE           NOT NULL,
    status_invoice invoice_status NOT NULL DEFAULT 'Overdue',
    CONSTRAINT chk_invoice_dates CHECK (due_date >= issue_date)
);

--yeh heavy wali cheez hai
CREATE TABLE FraudAlert (
    alert_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID         NOT NULL REFERENCES Transaction(transaction_id) ON DELETE CASCADE,
    reason         TEXT         NOT NULL,
    flag_date      DATE         NOT NULL DEFAULT CURRENT_DATE,
    status_fraud   fraud_status NOT NULL DEFAULT 'Detected'
);

--har cheez ki index bani hai lekin depending on functions/views wagerah ye change hoga
CREATE INDEX idx_useraccounts_bank        ON UserAccounts(bank_id);
CREATE INDEX idx_useraccounts_role        ON UserAccounts(role);
CREATE INDEX idx_riskscore_farmer         ON RiskScore(farmer_id);
CREATE INDEX idx_riskscore_date           ON RiskScore(calculated_date);
CREATE INDEX idx_loanapp_farmer           ON LoanApplication(farmer_id);
CREATE INDEX idx_loanapp_status           ON LoanApplication(status_application);
CREATE INDEX idx_loanapp_date             ON LoanApplication(application_date);
CREATE INDEX idx_loan_application         ON Loan(application_id);
CREATE INDEX idx_loan_bank                ON Loan(bank_id);
CREATE INDEX idx_loan_status              ON Loan(status_loan);
CREATE INDEX idx_collateral_farmer        ON Collateral(farmer_id);
CREATE INDEX idx_collateral_loan          ON Collateral(loan_id);
CREATE INDEX idx_collateral_claim         ON Collateral(claim_collateral);
CREATE INDEX idx_payment_loan             ON Payment(loan_id);
CREATE INDEX idx_payment_date             ON Payment(payment_date);
CREATE INDEX idx_transaction_farmer       ON Transaction(farmer_id);
CREATE INDEX idx_transaction_status       ON Transaction(status_trans);
CREATE INDEX idx_transaction_date         ON Transaction(date);
CREATE INDEX idx_invoice_farmer           ON Invoice(farmer_id);
CREATE INDEX idx_invoice_status           ON Invoice(status_invoice);
CREATE INDEX idx_invoice_due              ON Invoice(due_date);
CREATE INDEX idx_fraud_transaction        ON FraudAlert(transaction_id);
CREATE INDEX idx_fraud_status             ON FraudAlert(status_fraud);
CREATE INDEX idx_fraud_date               ON FraudAlert(flag_date);