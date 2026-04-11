--commands yahan se chori kiya hai
-- https://www.postgresql.org/docs/current/sql-commands.html
--gang syntax ka issue hosakta hai, please comments karke batadena
--enums are used for fixed "option" style inputs
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
CREATE TYPE app_status  AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE loan_status          AS ENUM ('Active', 'Closed');
CREATE TYPE payment_method       AS ENUM ('Cash', 'Online');
CREATE TYPE trans_type     AS ENUM ('Loan', 'Payment');
CREATE TYPE trans_status   AS ENUM ('Completed', 'Pending');
CREATE TYPE user_role            AS ENUM ('Admin', 'Loan Officer','Credit Analyst');
CREATE TYPE invoice_status       AS ENUM ('Paid', 'Overdue');
--changed from "Detected" to "Pending" kyunke fraud alert ke liye pending zyada sahi lagta hai, aur verified/dismissed uske baad aayenge
CREATE TYPE fraud_status AS ENUM ('Pending', 'Verified', 'Dismissed'); 


--idk agar yeh rakhna hai
CREATE TABLE B_User (
   user_id       SERIAL          PRIMARY KEY,
   Bank_name          VARCHAR(150)    NOT NULL,
   password      TEXT            NOT NULL
);

CREATE TABLE Farmer (
    farmer_id         SERIAL          PRIMARY KEY,
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
    farmer_id INT REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    area NUMERIC(10,2),
    location TEXT,
    soil_type TEXT
);

--idk how to incorporate this into the bank thingy

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
    --here too
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

--changed name from Transaction to Transactions because of error (reserved word hai)--
CREATE TABLE Transactions (
    transaction_id  SERIAL              PRIMARY KEY,
    farmer_id       INT                 NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    type            trans_type    NOT NULL, --enum use kiya hai and type kyunke mujhe kuch aur nahi yaad
    amount          NUMERIC(15, 2)      NOT NULL CHECK (amount > 0),
    date            DATE                NOT NULL DEFAULT CURRENT_DATE,
    status          trans_status  NOT NULL DEFAULT 'Pending'
);
 
CREATE TABLE FraudAlert (
    alert_id        SERIAL             PRIMARY KEY,
    transaction_id  INT                NOT NULL REFERENCES Transactions(transaction_id) ON DELETE CASCADE,
    reason          TEXT               NOT NULL,
    flag_date       DATE               NOT NULL DEFAULT CURRENT_DATE,
    status          fraud_status NOT NULL DEFAULT 'Pending'
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

CREATE OR REPLACE FUNCTION detect_fraud()
RETURNS TRIGGER AS $$
DECLARE
    avg_amount NUMERIC;
BEGIN
    -- get historical average
    SELECT AVG(amount)
    INTO avg_amount
    FROM Transactions
    WHERE farmer_id = NEW.farmer_id;

    -- RULE: if transaction > 2x average → fraud
    IF avg_amount IS NOT NULL AND NEW.amount > 2 * avg_amount THEN
        INSERT INTO FraudAlert (transaction_id, reason, status)
        VALUES (NEW.transaction_id, 'Unusual high transaction', 'Pending');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER fraud_trigger
AFTER INSERT ON Transactions
FOR EACH ROW
EXECUTE FUNCTION detect_fraud();