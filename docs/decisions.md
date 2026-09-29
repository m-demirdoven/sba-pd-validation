# Validation Log: Decisions and Findings

## 1. Data
- Source: Kaggle, "Should This Loan be Approved or Denied?" (U.S. SBA 7(a) loans, 1962-2014)
- Raw file: `SBAnational.csv`, 899,164 rows, loaded unchanged into `raw.sba_loans` (all columns TEXT)

## 2. Default definition
- **Default = 1** if `mis_status = 'CHGOFF'` OR a charge-off date is present
- **Default = 0** if `mis_status = 'P I F'` and no charge-off date
- Loans with missing `mis_status` (1,997 loans, 0.22%) are excluded
- Rationale: 4,927 loans are marked paid in full but carry a charge-off date. Consistent with Basel practice, a default that is later cured is still counted as a default ("closed default").
- Note: the target measures charge-off over the full life of the loan, not default within 12 months. Model output is therefore not directly comparable to a Basel 12-month PD.

## 3. Sample period
- **Development sample: 1989-2002**
- **Out-of-time monitoring sample: 2003-2008**
- Modelling population: 825,294 loans
- Before 1989 excluded: default rate is 100% up to 1980 and volume jumps from about 2,000 to 13,000 loans in 1989, which points to selection bias (only charged-off loans were kept in older records).
- After 2008 excluded: recent vintages had not completed their life when the data was extracted (right censoring), so their low default rates are misleading.
- Default rate rises from about 2% (1993) to 44% (2007), driven by rapid volume growth and the 2008 crisis.

## 4. Data quality findings

### Target and dates
| Field | Finding | Decision |
|---|---|---|
| `mis_status` | Stored as "P I F" (with spaces), not "PIF" | Standardise in clean layer |
| `approvalfy` | 18 loans with value "1976A" | Outside sample period, no impact |
| `chgoffdate` | 47 CHGOFF loans without a date | Keep as default |

### Categorical fields
| Field | Finding | Decision |
|---|---|---|
| `urbanrural` | Code 0 (undefined) for about 100% of loans before 1999, about 1% after 2000. The field was not collected in early years. | **Excluded.** It would act as a proxy for approval year. |
| `revlinecr` | Only 67% Y/N. Code "0" appears from 1995, peaks at 60% in 1999, falls to about 20% by 2007. Also "T" and keyboard errors. The Unknown group behaves like N (see numeric checks). | Keep as Y / N / Unknown. Merge Unknown with N if default rates confirm. |
| `lowdoc` | 0.4% invalid values | Mapped to Unknown |
| `newexist` | 0.1% coded 0 | Mapped to Unknown |
| `naics` | Code 0 (missing) for about 55% of loans 1989-1998, about 42% in 1999-2000, about 0% from 2001. Within each year, missing codes show a slightly higher default rate (0.1 to 1.8 pp, same direction in all 12 years). The gap is small, so leakage risk is assessed as low. | Keep 2-digit sector, missing as Unknown. Stability shift expected. |

### Numeric fields
All amount, term, employee and NAICS values match the expected format (0 errors).

| Field | Finding | Decision |
|---|---|---|
| `disbursementgross` | Exceeds approved amount for 70.6% of revolving lines vs 1.1% of non-revolving loans. It measures cumulative drawdowns on revolvers, not loan size. | **Excluded.** `grappv` used as loan size. |
| `sba_appv` | Never exceeds approved amount | Clean. Used to derive guarantee share. |
| `term` | 775 loans with term 0 (invalid). 2,808 loans above 300 months (max 569), almost all non-revolving. | Term 0 as Unknown, cap at 300 months |
| `noemp` | 4,002 firms with 0 employees, 3 with code 9999 | 0 kept as its own group, 9999 as Unknown |

## 5. Expected stability issues
These variables are expected to show population shift between development and monitoring periods because of data collection changes, not changes in credit risk:
- `revlinecr`: share of Unknown codes changes over time
- `naics`: Unknown sector exists almost only in the development period