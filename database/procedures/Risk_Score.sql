-- VIEW: Risk Assessment (Ministry of Finance Pakistan)
CREATE VIEW risk_assessment_mof AS
WITH
layer_1_ratio_calculation AS (
    SELECT
        f.application_id,
        r.is_in_arrears,
        (ff.annual_revenue - ff.operating_expenses) / NULLIF(ff.annual_revenue, 0)       AS ebitda_margin,
        ff.net_income / NULLIF(ff.total_assets, 0)                                        AS roa,
        ff.current_assets / NULLIF(ff.current_liabilities, 0)                            AS current_ratio,
        ff.total_debt / NULLIF(c.land_value - ff.total_debt, 0)                          AS de_ratio,
        (ff.annual_revenue - ff.operating_expenses) / NULLIF(ff.annual_debt_service, 0)  AS dscr,
        r.sector_risk_value,
        r.governance_value
    FROM LoanApplication f
    JOIN (
        SELECT DISTINCT ON (farmer_id) *
        FROM farmer_finance
        ORDER BY farmer_id, reported_date DESC
    ) ff ON f.farmer_id = ff.farmer_id
    JOIN (
        SELECT loan_id, SUM(land_value) AS land_value
        FROM Collateral
        GROUP BY loan_id
    ) c ON c.loan_id = (
        SELECT l.loan_id
        FROM Loan l
        WHERE l.application_id = f.application_id
        LIMIT 1
    )
    JOIN (
        SELECT DISTINCT ON (farmer_id) *
        FROM RiskScore
        ORDER BY farmer_id, calculated_date DESC
    ) r ON f.farmer_id = r.farmer_id
),
layer_2_score_calculation AS (
    SELECT
        application_id,
        CASE
            WHEN is_in_arrears         THEN 4
            WHEN ebitda_margin >= 0.50 THEN 1
            WHEN ebitda_margin >= 0.30 THEN 2
            WHEN ebitda_margin >= 0.10 THEN 3
            ELSE 4
        END AS profitability_score_ebitda_margin,
        CASE
            WHEN roa >= 0.20                THEN 1
            WHEN roa >= 0.10 AND roa < 0.20 THEN 2
            WHEN roa >= 0.05 AND roa < 0.10 THEN 3
            ELSE 4
        END AS profitability_score_roa,
        CASE
            WHEN current_ratio >= 1.20                          THEN 1
            WHEN current_ratio >= 1.00 AND current_ratio < 1.20 THEN 2
            WHEN current_ratio >= 0.80 AND current_ratio < 1.00 THEN 3
            ELSE 4
        END AS liquidity_score_current_ratio,
        CASE
            WHEN de_ratio < 0.40                      THEN 1
            WHEN de_ratio >= 0.40 AND de_ratio < 0.80 THEN 2
            WHEN de_ratio >= 0.80 AND de_ratio < 1.20 THEN 3
            ELSE 4
        END AS solvency_score_de_ratio,
        CASE
            WHEN dscr > 1.50                   THEN 1
            WHEN dscr >= 1.20 AND dscr <= 1.50 THEN 2
            WHEN dscr >= 1.00 AND dscr <  1.20 THEN 3
            ELSE 4
        END AS debt_service_coverage_score_dscr,
        CASE
            WHEN governance_value >= 10                          THEN 1
            WHEN governance_value >= 5 AND governance_value < 10 THEN 2
            WHEN governance_value >= 2 AND governance_value < 5  THEN 3
            ELSE 4
        END AS governance_score,
        CASE
            WHEN sector_risk_value >= 8                             THEN 1
            WHEN sector_risk_value >= 5 AND sector_risk_value < 8  THEN 2
            WHEN sector_risk_value >= 3 AND sector_risk_value < 5  THEN 3
            ELSE 4
        END AS sector_risk_score
    FROM layer_1_ratio_calculation
),
layer_3_final_scores AS (
    SELECT
        application_id,
        ROUND(
            profitability_score_ebitda_margin * (10.0 / 55) +
            profitability_score_roa           * (10.0 / 55) +
            liquidity_score_current_ratio     * (10.0 / 55) +
            solvency_score_de_ratio           * (15.0 / 55) +
            debt_service_coverage_score_dscr  * (10.0 / 55), 2) AS financial_profile_score,
        ROUND(
            sector_risk_score * (20.0 / 35) +
            governance_score  * (15.0 / 35), 2) AS business_profile_score,
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
    la.application_code,                                         
    f.farmer_code,                                                
    financial_profile_score,
    business_profile_score,
    overall_risk_score,
    CASE
        WHEN overall_risk_score BETWEEN 1.0 AND 1.4 THEN 'Low Risk'
        WHEN overall_risk_score BETWEEN 1.5 AND 2.4 THEN 'Moderate Risk'
        WHEN overall_risk_score BETWEEN 2.5 AND 3.4 THEN 'Elevated Risk'
        ELSE 'High Risk'
    END AS risk_level
FROM layer_3_final_scores ls
JOIN LoanApplication la ON ls.application_id = la.application_id
JOIN Farmer f ON la.farmer_id = f.farmer_id;                    


