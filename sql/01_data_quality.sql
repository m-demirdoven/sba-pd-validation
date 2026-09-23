-- =====================================================
-- 01_data_quality.sql
-- Data quality checks on raw SBA loan data
-- =====================================================

-- 1. Target variable distribution
SELECT
    mis_status,
    COUNT(*) AS n_loans,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM raw.sba_loans
GROUP BY mis_status
ORDER BY n_loans DESC;

-- 2. Consistency between loan status and charge-off date
-- Expectation: CHGOFF loans have a charge-off date, PIF loans do not
SELECT
    mis_status,
    CASE
        WHEN NULLIF(TRIM(chgoffdate), '') IS NULL THEN 'no_date'
        ELSE 'has_date'
    END AS chgoff_date_flag,
    COUNT(*) AS n_loans
FROM raw.sba_loans
GROUP BY 1, 2
ORDER BY 1, 2;


-- 3. Approval fiscal year: values that are not a valid 4-digit year
SELECT
    approvalfy,
    COUNT(*) AS n_loans
FROM raw.sba_loans
WHERE approvalfy IS NULL
   OR approvalfy !~ '^[0-9]{4}$'
GROUP BY approvalfy
ORDER BY n_loans DESC;

-- 4. Loan volume and default rate by approval year
-- Default definition: CHGOFF status OR has a charge-off date
-- Loans with missing status are excluded
SELECT
    LEFT(approvalfy, 4)::INT AS approval_year,
    COUNT(*) AS n_loans,
    ROUND(100.0 * AVG(
        CASE
            WHEN mis_status = 'CHGOFF'
              OR NULLIF(TRIM(chgoffdate), '') IS NOT NULL THEN 1
            ELSE 0
        END
    ), 2) AS default_rate_pct
FROM raw.sba_loans
WHERE mis_status IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- 5. Categorical fields: value distribution
-- Population: approval years 1989-2008, known loan status
WITH pop AS (
    SELECT *
    FROM raw.sba_loans
    WHERE mis_status IS NOT NULL
      AND LEFT(approvalfy, 4)::INT BETWEEN 1989 AND 2008
)
SELECT 'newexist' AS field, newexist AS value, COUNT(*) AS n_loans
FROM pop GROUP BY newexist
UNION ALL
SELECT 'urbanrural', urbanrural, COUNT(*)
FROM pop GROUP BY urbanrural
UNION ALL
SELECT 'revlinecr', revlinecr, COUNT(*)
FROM pop GROUP BY revlinecr
UNION ALL
SELECT 'lowdoc', lowdoc, COUNT(*)
FROM pop GROUP BY lowdoc
ORDER BY field, n_loans DESC;

-- 6. Coding changes over time: share of suspicious codes by approval year
SELECT
    LEFT(approvalfy, 4)::INT AS approval_year,
    COUNT(*) AS n_loans,
    ROUND(100.0 * AVG(CASE WHEN revlinecr = '0' THEN 1 ELSE 0 END), 1) AS revlinecr_zero_pct,
    ROUND(100.0 * AVG(CASE WHEN revlinecr = 'T' THEN 1 ELSE 0 END), 1) AS revlinecr_t_pct,
    ROUND(100.0 * AVG(CASE WHEN urbanrural = '0' THEN 1 ELSE 0 END), 1) AS urbanrural_zero_pct
FROM raw.sba_loans
WHERE mis_status IS NOT NULL
  AND LEFT(approvalfy, 4)::INT BETWEEN 1989 AND 2008
GROUP BY 1
ORDER BY 1;