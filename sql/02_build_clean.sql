-- =====================================================
-- 02_build_clean.sql
-- Build the modelling table by applying the decisions
-- documented in docs/decisions.md
-- =====================================================

DROP TABLE IF EXISTS clean.sba_loans;

CREATE TABLE clean.sba_loans AS
SELECT
    loannr_chkdgt AS loan_id,
    LEFT(approvalfy, 4)::INT AS approval_year,

    -- Sample split
    CASE
        WHEN LEFT(approvalfy, 4)::INT <= 2002 THEN 'development'
        ELSE 'monitoring'
    END AS sample,

    -- Target: charge-off status OR charge-off date present (closed default)
    CASE
        WHEN mis_status = 'CHGOFF'
          OR NULLIF(TRIM(chgoffdate), '') IS NOT NULL THEN 1
        ELSE 0
    END AS default_flag,

    -- Loan size and guarantee share
    REPLACE(REPLACE(TRIM(grappv), '$', ''), ',', '')::NUMERIC AS loan_amount,
    ROUND(
        REPLACE(REPLACE(TRIM(sba_appv), '$', ''), ',', '')::NUMERIC
      / REPLACE(REPLACE(TRIM(grappv), '$', ''), ',', '')::NUMERIC
    , 4) AS guarantee_share,

    -- Term: 0 is invalid, cap at 300 months
    CASE
        WHEN term::INT = 0 THEN NULL
        ELSE LEAST(term::INT, 300)
    END AS term_months,

    -- Employees: 9999 is a placeholder code
    CASE
        WHEN noemp::INT >= 9999 THEN NULL
        ELSE noemp::INT
    END AS n_employees,

    -- Categorical fields with Unknown for invalid codes
    CASE newexist
        WHEN '1' THEN 'Existing'
        WHEN '2' THEN 'New'
        ELSE 'Unknown'
    END AS business_type,

    CASE
        WHEN revlinecr IN ('Y', 'N') THEN revlinecr
        ELSE 'Unknown'
    END AS revolving,

    CASE
        WHEN lowdoc IN ('Y', 'N') THEN lowdoc
        ELSE 'Unknown'
    END AS lowdoc,

    CASE
        WHEN naics = '0' THEN 'Unknown'
        ELSE LEFT(naics, 2)
    END AS sector,

    state

    -- Excluded: urbanrural (not collected before 2000),
    -- disbursementgross (cumulative drawdowns on revolvers)
FROM raw.sba_loans
WHERE mis_status IS NOT NULL
  AND LEFT(approvalfy, 4)::INT BETWEEN 1989 AND 2008;

-- Sanity check: size and default rate by sample
SELECT
    sample,
    COUNT(*) AS n_loans,
    SUM(default_flag) AS n_defaults,
    ROUND(100.0 * AVG(default_flag), 2) AS default_rate_pct
FROM clean.sba_loans
GROUP BY sample
ORDER BY sample;