--commands From this website
-- https://www.postgresql.org/docs/current/sql-commands.html
--enums are used for fixed "option" style inputs

CREATE TYPE app_status  AS ENUM ('Pending', 'Approved', 'Rejected');
CREATE TYPE loan_status          AS ENUM ('Active', 'Closed');
CREATE TYPE payment_method       AS ENUM ('Cash', 'Online');
CREATE TYPE trans_type     AS ENUM ('Loan', 'Payment');
CREATE TYPE trans_status   AS ENUM ('Completed', 'Pending');
CREATE TYPE user_role            AS ENUM ('Admin', 'Loan Officer','Credit Analyst');
CREATE TYPE invoice_status       AS ENUM ('Paid', 'Overdue');
CREATE TYPE fraud_status   AS ENUM ('Detected', 'Undetected');
CREATE TYPE status_gurantor AS ENUM('Accepted', 'Rejected');
CREATE TYPE land_type AS ENUM('Irrigated', 'Non-Irrigated', 'Pasture');
CREATE TYPE claim_collateral AS ENUM('Claimed', 'Non-Claimed', 'Partially Claimed');
--UUID-> Universally Unique Identifier, a 128-bit number used to uniquely identify information in computer systems. 
---It is useful for security, scalabilty and effects the performance of the database.

CREATE TABLE Banks(--Centralized banking as we need to keep track of the banks and their relationship with the farmers and the loans.
    bank_id UUID PRIMARY KEY DEFAULT gen_uuid7(),
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
-- ADded Gurantor to keep track for gurantors.
CREATE TABLE Gurantor(--its needed as we need to keep track of the gurantors and their relationship with the farmers and the loans. It will also help with fraud detection and risk assessment.
gurantor_id UUID PRIMARY KEY DEFAULT gen_uuidv7(),
loan_id     INT             NOT NULL REFERENCES Loan(loan_id) ON DELETE CASCADE,
cnic        VARCHAR(15)     NOT NULL UNIQUE,
phone       VARCHAR(20),
relationship VARCHAR(50),--realtionship with farmer (we can also make this enum)
status_gurantor status_gurantor NOT NULL DEFAULT 'Accepted'--gurantor can accept or reject the guarantorship
);
CREATE TABLE Farmer (
    farmer_id        UUID PRIMARY KEY DEFAULT gen_uuidv7(),--as for security and scalability
    name              VARCHAR(150)    NOT NULL,
    cnic              VARCHAR(15)     NOT NULL UNIQUE, 
    phone             VARCHAR(20),
    address           TEXT,
    registration_date DATE            NOT NULL DEFAULT CURRENT_DATE,
	collateral_id      INT            REFERENCES Collateral(collateral_id) ON DELETE SET NULL,
	gurantor_id UUID REFERENCES Gurantor(gurantor_id) ON DELETE SET NULL,
	Eligibility		BOOL,--not sure--YES /NO
	Fraud_alert     BOOL,--not sure
    Credit_History  BOOL--not sure
);
--added land as collateral
--will help with fraud detection
CREATE TABLE Collateral(--important as if we add only a attribute it will not work as we need to keep track of the collateral and its relationship with the farmers and the loans. It will also help with fraud detection and risk assessment.
collateral_id SERIAL PRIMARY KEY,
loan_id     INT             NOT NULL REFERENCES Loan(loan_id) ON DELETE CASCADE,
farmer_id   INT             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
land_value   NUMERIC(15, 2)  NOT NULL CHECK (land_value > 0),--better than land size as it can be used for risk assessment and loan approval process
land_type  land_type NOT NULL,--land type as most banks use value of land as collateral and it can be used for risk assessment and loan approval process
claim_collateral claim_collateral NOT NULL DEFAULT 'Non-Claimed' --for detection whether if any bank has already claimed it as a collateral or not
);
--riskscore
CREATE TABLE RiskScore (
    risk_id          SERIAL          PRIMARY KEY,
    farmer_id        INT             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,  --delete kyunke faida nahi isse rakhne ka
    score_value      NUMERIC(5, 2)   NOT NULL,  
    calculated_date  DATE            NOT NULL DEFAULT CURRENT_DATE,
    remarks          TEXT
);
--loan application table
CREATE TABLE LoanApplication (
    application_id     UUID PRIMARY KEY DEFAULT gen_uuidv7(),
    farmer_id         INT                 NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    requested_amount  NUMERIC(15, 2)      NOT NULL,
    purpose           TEXT,
    fraud_alert       BOOLEAN             NOT NULL DEFAULT FALSE,--not sure
    risk_score        NUMERIC(5, 2),    ---not sure               
    application_date  DATE                NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,--added timestamp as importnat feature 
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status_application            app_status  NOT NULL DEFAULT 'Pending' --naya seekha hai values dalne ke baad hi pata chalega
);
--loan table
CREATE TABLE Loan (
    loan_id          UUID PRIMARY KEY DEFAULT gen_uuidv7(),
    application_id   INT           NOT NULL UNIQUE REFERENCES LoanApplication(application_id) ON DELETE RESTRICT,
    approved_amount  NUMERIC(15, 2) NOT NULL,
    interest_rate    NUMERIC(5, 2)  NOT NULL,   --again not sure if we are going with interest
    start_date       DATE          NOT NULL,
    end_date         DATE          NOT NULL,
    status_loan           loan_status   NOT NULL DEFAULT 'Active',
    CONSTRAINT chk_loan_dates CHECK (end_date > start_date)
);

--also like a lot of dependent "references" thingy so might have a few errors
CREATE TABLE Payment (
    payment_id      SERIAL          PRIMARY KEY,
    loan_id         INT             NOT NULL REFERENCES Loan(loan_id) ON DELETE RESTRICT,
    amount_paid     NUMERIC(15, 2)  NOT NULL CHECK (amount_paid > 0),
    payment_date    DATE            NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    payment_method  payment_method  NOT NULL
);

-- Trascation table
CREATE TABLE Transaction (
    transaction_id  SERIAL          PRIMARY KEY,
    farmer_id       INT                 NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
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
    transaction_id  INT                NOT NULL REFERENCES Transaction(transaction_id) ON DELETE CASCADE,
    reason          TEXT               NOT NULL,
    flag_date       DATE               NOT NULL DEFAULT CURRENT_DATE,
    status_fraud          fraud_status NOT NULL DEFAULT 'Detected'
);
--Invoice Table
CREATE TABLE Invoice (
    invoice_id   SERIAL          PRIMARY KEY,
    invoice_no   VARCHAR(50)     NOT NULL UNIQUE,
    farmer_id    INT             NOT NULL REFERENCES Farmer(farmer_id) ON DELETE CASCADE,
    amount       NUMERIC(15, 2)  NOT NULL CHECK (amount > 0),
    issue_date   DATE            NOT NULL DEFAULT CURRENT_DATE,
    due_date     DATE            NOT NULL,
    status_invoice       invoice_status  NOT NULL DEFAULT 'Overdue',
    CONSTRAINT chk_invoice_dates CHECK (due_date >= issue_date)
);
