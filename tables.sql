--commands yahan se chori kiya hai
-- https://www.postgresql.org/docs/current/sql-commands.html
--gang syntax ka issue hosakta hai please comments karke batadena

--enums are used for fixed "option" style inputs
CREATE TYPE app_status  AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE loan_status          AS ENUM ('Active', 'Closed');
CREATE TYPE payment_method       AS ENUM ('Cash', 'Online');
CREATE TYPE trans_type     AS ENUM ('Loan', 'Payment');
CREATE TYPE trans_status   AS ENUM ('Completed', 'Pending');
CREATE TYPE user_role            AS ENUM ('Admin', 'Officer');
CREATE TYPE invoice_status       AS ENUM ('Paid', 'Overdue');
CREATE TYPE fraud_status   AS ENUM ('Open', 'Resolved');

--idk agar yeh rakhna hai
--CREATE TABLE B_User (
--    user_id       SERIAL          PRIMARY KEY,
--    name          VARCHAR(150)    NOT NULL,
--    email         VARCHAR(255)    NOT NULL UNIQUE,
--    password      TEXT            NOT NULL,  
--    role          user_role       NOT NULL
--);

--also batana land ko kaise kar sakti hun thori confused hun

--idk how to incorporate this into the bank thingy
CREATE TABLE Farmer (
    farmer_id         SERIAL          PRIMARY KEY,
    name              VARCHAR(150)    NOT NULL,
    cnic              VARCHAR(15)     NOT NULL UNIQUE, 
    phone             VARCHAR(20),
    address           TEXT,
    registration_date DATE            NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE RiskScore (
    risk_id          SERIAL          PRIMARY KEY,
    farmer_id        INT             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,  --delete kyunke faida nahi isse rakhne ka
    score_value      NUMERIC(5, 2)   NOT NULL,  
    calculated_date  DATE            NOT NULL DEFAULT CURRENT_DATE,
    remarks          TEXT
);
 
CREATE TABLE LoanApplication (
    application_id    SERIAL              PRIMARY KEY,
    farmer_id         INT                 NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    requested_amount  NUMERIC(15, 2)      NOT NULL,
    purpose           TEXT,
    fraud_alert       BOOLEAN             NOT NULL DEFAULT FALSE,
    risk_score        NUMERIC(5, 2),                   
    application_date  DATE                NOT NULL DEFAULT CURRENT_DATE,
    status            app_status  NOT NULL DEFAULT 'Pending' --naya seekha hai values dalne ke baad hi pata chalega
);

CREATE TABLE Loan (
    loan_id          SERIAL        PRIMARY KEY,
    application_id   INT           NOT NULL UNIQUE REFERENCES LoanApplication(application_id) ON DELETE RESTRICT,
    approved_amount  NUMERIC(15, 2) NOT NULL,
    interest_rate    NUMERIC(5, 2)  NOT NULL,   --again not sure if we are going with interest
    start_date       DATE          NOT NULL,
    end_date         DATE          NOT NULL,
    status           loan_status   NOT NULL DEFAULT 'Active',
    CONSTRAINT chk_loan_dates CHECK (end_date > start_date)
);

--also like a lot of dependent "references" thingy so might have a few errors
CREATE TABLE Payment (
    payment_id      SERIAL          PRIMARY KEY,
    loan_id         INT             NOT NULL REFERENCES Loan(loan_id) ON DELETE RESTRICT,
    amount_paid     NUMERIC(15, 2)  NOT NULL CHECK (amount_paid > 0),
    payment_date    DATE            NOT NULL DEFAULT CURRENT_DATE,
    payment_method  payment_method  NOT NULL
);

-- !! Batana payment alag hai from transaction
CREATE TABLE Transaction (
    transaction_id  SERIAL              PRIMARY KEY,
    farmer_id       INT                 NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    type            trans_type    NOT NULL, --enum use kiya hai and type kyunke mujhe kuch aur nahi yaad
    amount          NUMERIC(15, 2)      NOT NULL CHECK (amount > 0),
    date            DATE                NOT NULL DEFAULT CURRENT_DATE,
    status          trans_status  NOT NULL DEFAULT 'Pending'
);
 
CREATE TABLE FraudAlert (
    alert_id        SERIAL             PRIMARY KEY,
    transaction_id  INT                NOT NULL REFERENCES Transaction(transaction_id) ON DELETE CASCADE,
    reason          TEXT               NOT NULL,
    flag_date       DATE               NOT NULL DEFAULT CURRENT_DATE,
    status          fraud_status NOT NULL DEFAULT 'Open'
);

CREATE TABLE Invoice (
    invoice_id   SERIAL          PRIMARY KEY,
    farmer_id    INT             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    amount       NUMERIC(15, 2)  NOT NULL CHECK (amount > 0),
    issue_date   DATE            NOT NULL DEFAULT CURRENT_DATE,
    due_date     DATE            NOT NULL,
    status       invoice_status  NOT NULL DEFAULT 'Overdue',
    CONSTRAINT chk_invoice_dates CHECK (due_date >= issue_date)
);

--also according to geeksforgeeks we can incorporate indexes sir ne aaj parhaya hai