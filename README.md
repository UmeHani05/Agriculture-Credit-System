# Agriculture Credit System

## Overview

The Agriculture Credit System is a database-driven financial management platform designed to support agricultural lending through structured data management and risk-based credit evaluation.

The system centralizes farmer, loan, invoice, transaction, and repayment data to improve loan assessment, monitor financial activities, reduce fraud, and support analytical reporting for financial institutions.

---

## Objectives

- Manage agricultural and financial records in a centralized database
- Support data-driven loan approval and risk assessment
- Track invoices, repayments, and overdue balances
- Detect suspicious financial transactions
- Maintain secure and consistent financial records
- Provide reporting and analytical insights

---

## Core Features

### Farmer and Loan Management
- Farmer registration and profile management
- Land and crop record management
- Loan application and approval workflow
- Loan repayment tracking
- Risk score generation based on historical records

### Invoice and Payment Management
- Invoice generation and storage
- Payment tracking and invoice status updates
- Outstanding balance monitoring
- Invoice aging analysis

### Transaction and Fraud Monitoring
- Real-time transaction logging
- Fraud flag generation using transaction patterns
- Suspicious activity monitoring
- Administrative fraud review system

### Reporting and Analytics
- Loan approval and rejection reports
- Repayment performance reports
- Invoice aging summaries
- Fraud analysis reports

### Security and Access Control
- Role-based access control
- Secure data validation
- Controlled access for administrators and loan officers

---

## Technology Stack

| Component | Technology |
|---|---|
| Database | PostgreSQL |
| Backend | Node.js |
| Frontend | HTML, CSS, JavaScript |
| Deployment | Firebase |
| Project Management | Jira |
| Version Control | GitHub |

---

## Repository Structure

```text
Agriculture-Credit-System/
│
├── README.md
│
├── docs/
│   ├── Proposal.pdf
│   ├── ERD.png
│   └── Schema.png
│
├── database/
│   │
│   ├── schema/
│   │   ├── tables.sql
│   │   ├── updated_final_code.sql
│   │   └── uuid_v7.sql
│   │
│   ├── procedures/
│   │   ├── risk_score.sql
│   │   ├── fraud_detection.sql
│   │   └── invoice_aging.sql
│   │
│   └── backups/
│       ├── final_draft_schema.sql
│       ├── table_code_revised.sql
│       └── tables_merged_risk_score.sql

### ERD MAPPED
<img width="1006" height="1044" alt="asc_erd drawio (3)" src="https://github.com/user-attachments/assets/8403386e-a371-4d77-b55f-739c69f114a4" />

### Team
Aleena Jamil (2024081)
Areej Arif Khan (2024113)
Ume Hani Tufail (2024646)
