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


-- 7. Numeric fields: values that do not match the expected format
-- Population: approval years 1989-2008, known loan status
WITH pop AS (
    SELECT *
    FROM raw.sba_loans
    WHERE mis_status IS NOT NULL
      AND LEFT(approvalfy, 4)::INT BETWEEN 1989 AND 2008
)
SELECT
    COUNT(*) AS n_loans,
    SUM(CASE WHEN grappv            !~ '^\$[0-9,]+\.[0-9]{2}\s*$' OR grappv IS NULL            THEN 1 ELSE 0 END) AS bad_grappv,
    SUM(CASE WHEN sba_appv          !~ '^\$[0-9,]+\.[0-9]{2}\s*$' OR sba_appv IS NULL          THEN 1 ELSE 0 END) AS bad_sba_appv,
    SUM(CASE WHEN disbursementgross !~ '^\$[0-9,]+\.[0-9]{2}\s*$' OR disbursementgross IS NULL THEN 1 ELSE 0 END) AS bad_disbursement,
    SUM(CASE WHEN term              !~ '^[0-9]+$'                 OR term IS NULL              THEN 1 ELSE 0 END) AS bad_term,
    SUM(CASE WHEN noemp             !~ '^[0-9]+$'                 OR noemp IS NULL             THEN 1 ELSE 0 END) AS bad_noemp,
    SUM(CASE WHEN naics             !~ '^[0-9]+$'                 OR naics IS NULL             THEN 1 ELSE 0 END) AS bad_naics
FROM pop;

-- 8. Numeric fields: range and distribution
-- Population: approval years 1989-2008, known loan status
WITH pop AS (
    SELECT
        REPLACE(REPLACE(TRIM(grappv), '$', ''), ',', '')::NUMERIC            AS grappv,
        REPLACE(REPLACE(TRIM(sba_appv), '$', ''), ',', '')::NUMERIC          AS sba_appv,
        REPLACE(REPLACE(TRIM(disbursementgross), '$', ''), ',', '')::NUMERIC AS disbursement,
        term::NUMERIC  AS term,
        noemp::NUMERIC AS noemp
    FROM raw.sba_loans
    WHERE mis_status IS NOT NULL
      AND LEFT(approvalfy, 4)::INT BETWEEN 1989 AND 2008
),
long_format AS (
    SELECT 'grappv' AS field, grappv AS value FROM pop
    UNION ALL SELECT 'sba_appv', sba_appv FROM pop
    UNION ALL SELECT 'disbursement', disbursement FROM pop
    UNION ALL SELECT 'term', term FROM pop
    UNION ALL SELECT 'noemp', noemp FROM pop
)
SELECT
    field,
    MIN(value) AS min_value,
    PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY value) AS p01,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY value) AS median,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY value) AS p99,
    MAX(value) AS max_value,
    SUM(CASE WHEN value = 0 THEN 1 ELSE 0 END) AS n_zero
FROM long_format
GROUP BY field
ORDER BY field;


-- 9. Numeric anomalies, split by revolving line flag
-- Population: approval years 1989-2008, known loan status
WITH pop AS (
    SELECT
        CASE
            WHEN revlinecr IN ('Y', 'N') THEN revlinecr
            ELSE 'Unknown'
        END AS revline_group,
        REPLACE(REPLACE(TRIM(grappv), '$', ''), ',', '')::NUMERIC            AS grappv,
        REPLACE(REPLACE(TRIM(sba_appv), '$', ''), ',', '')::NUMERIC          AS sba_appv,
        REPLACE(REPLACE(TRIM(disbursementgross), '$', ''), ',', '')::NUMERIC AS disbursement,
        term::INT  AS term,
        noemp::INT AS noemp
    FROM raw.sba_loans
    WHERE mis_status IS NOT NULL
      AND LEFT(approvalfy, 4)::INT BETWEEN 1989 AND 2008
)
SELECT
    revline_group,
    COUNT(*) AS n_loans,
    SUM(CASE WHEN disbursement > grappv THEN 1 ELSE 0 END) AS disb_above_approved,
    ROUND(100.0 * AVG(CASE WHEN disbursement > grappv THEN 1 ELSE 0 END), 1) AS disb_above_approved_pct,
    SUM(CASE WHEN sba_appv > grappv THEN 1 ELSE 0 END) AS guarantee_above_approved,
    SUM(CASE WHEN term = 0 THEN 1 ELSE 0 END)   AS term_zero,
    SUM(CASE WHEN term > 300 THEN 1 ELSE 0 END) AS term_above_300,
    SUM(CASE WHEN noemp = 0 THEN 1 ELSE 0 END)  AS noemp_zero,
    SUM(CASE WHEN noemp >= 9999 THEN 1 ELSE 0 END) AS noemp_9999
FROM pop
GROUP BY revline_group
ORDER BY revline_group;

-- 10. NAICS sector code: share of missing codes (0) by approval year
SELECT
    LEFT(approvalfy, 4)::INT AS approval_year,
    COUNT(*) AS n_loans,
    SUM(CASE WHEN naics = '0' THEN 1 ELSE 0 END) AS naics_missing,
    ROUND(100.0 * AVG(CASE WHEN naics = '0' THEN 1 ELSE 0 END), 1) AS naics_missing_pct
FROM raw.sba_loans
WHERE mis_status IS NOT NULL
  AND LEFT(approvalfy, 4)::INT BETWEEN 1989 AND 2008
GROUP BY 1
ORDER BY 1;


-- 11. Is missing NAICS related to the outcome? (possible leakage)
-- Compare default rates of coded vs missing NAICS within each approval year
WITH pop AS (
    SELECT
        LEFT(approvalfy, 4)::INT AS approval_year,
        naics,
        CASE
            WHEN mis_status = 'CHGOFF'
              OR NULLIF(TRIM(chgoffdate), '') IS NOT NULL THEN 1
            ELSE 0
        END AS default_flag
    FROM raw.sba_loans
    WHERE mis_status IS NOT NULL
      AND LEFT(approvalfy, 4)::INT BETWEEN 1989 AND 2000
)
SELECT
    approval_year,
    COUNT(*) FILTER (WHERE naics = '0')  AS n_missing,
    COUNT(*) FILTER (WHERE naics <> '0') AS n_coded,
    ROUND(100.0 * AVG(default_flag) FILTER (WHERE naics = '0'), 2)  AS default_rate_missing,
    ROUND(100.0 * AVG(default_flag) FILTER (WHERE naics <> '0'), 2) AS default_rate_coded
FROM pop
GROUP BY approval_year
ORDER BY approval_year;