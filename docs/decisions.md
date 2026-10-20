# Validation Log: Decisions and Findings

## 1. Data
- Source: Kaggle, "Should This Loan be Approved or Denied?" (U.S. SBA 7(a) loans, 1962-2014)
- Raw file: `SBAnational.csv`, 899,164 rows, loaded unchanged into `raw.sba_loans` (all columns TEXT)

## 2. Default definition
- **Default = 1** if `mis_status = 'CHGOFF'` OR a charge-off date is present
- **Default = 0** if `mis_status = 'P I F'` and no charge-off date
- Loans with missing `mis_status` (1,997 loans, 0.22%) are excluded
- Of these 1,997 loans, 261 have a charge-off date. They are excluded together with the rest of the group because the status field is incomplete. Counting them as defaults would change the default rate by less than 0.1 pp in each sample.
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

## 6. Replication in SAS
- The raw data import, all 11 data quality checks and the clean modelling table were rebuilt in SAS as a second implementation (`sas/` folder).
- All results match the PostgreSQL figures in this log: 899,164 raw rows, 825,294 loans in the modelling population, 435,278 development loans (6.92% default rate) and 390,016 monitoring loans (30.10% default rate).

## 7. Univariate analysis (development sample only)
Decisions in this section use the development sample only, so the out-of-time test stays clean.

### Method: year-adjusted risk index
The default rate rises from about 2% (1993) to 12% (2002) within the development sample. Any variable whose mix changes over time picks up this trend and can look like a risk driver when it is not. Each category is therefore compared with loans approved in the same year:
- Risk index = observed defaults / expected defaults, where expected = default rate of all development loans approved in the same year
- Index above 1 means riskier than the average loan of the same year

### Decisions
| Variable | Finding | Decision |
|---|---|---|
| `revolving` (`revlinecr`) | Pooled default rate: N 4.8%, Unknown 10.3%, Y 10.8%. Within each year Y and N are almost equal (1999: 8.8% vs 8.3%, 2000: 10.2% vs 10.7%). The pooled gap comes from Y loans being concentrated in 2000-2002. Unknown is 1.0 to 2.2 pp above N within year, but it is a recording code whose share falls from 60% to 20%. | **Excluded.** Replaces the decision in section 4. |
| `business_type` (`newexist`) | New is riskier than Existing in all 14 years (1999: 12.8% vs 8.9%). | Keep. Unknown (673 loans) merged with Existing. |
| `lowdoc` | The program starts in 1994. From then Y is riskier than N in every year, and the gap grows from 0.3 to 3.5 pp. | Keep. Unknown (1,924 loans) merged with N. |
| `sector` (`naics`) | Year adjustment changes the ranking: food services 11.6% raw but index 1.07, agriculture 7.2% raw but index 1.19, Unknown 5.8% raw but index 1.06. | Four groups by index (see below). Unknown joins S2. |
| `state` | Index from 0.58 (MT) to 1.77 (KY, AR). 9 development loans have no state. | Four groups by index (see below). Missing state joins T3. |

### Sector groups (2-digit NAICS)
| Group | Codes | Loans | Default rate | Index |
|---|---|---|---|---|
| S1 high | 45 | 18,357 | 11.07% | 1.51 |
| S2 above average | 11, 31, 32, 44, 48, 49, 51, 53, 71, 72, Unknown | 270,915 | 6.89% | 1.07 |
| S3 below average | 23, 33, 42, 56, 61, 81 | 97,640 | 7.27% | 0.93 |
| S4 low | 21, 22, 52, 54, 55, 62, 92 | 48,366 | 4.81% | 0.63 |

S2 has a lower raw default rate than S3 because it contains the Unknown loans from early, low-default years. The model must control for approval year, otherwise it will learn the raw order.

### State groups
Cut points at index 1.25, 1.00 and 0.80.

| Group | States | Loans | Default rate | Index |
|---|---|---|---|---|
| T1 high | AL, AR, IL, KY, LA, MS, OK, SC, TN, TX, WV | 85,753 | 9.16% | 1.40 |
| T2 above average | CO, DE, FL, GA, IN, KS, MI, MO, NC, NM, NV, NY, OH | 122,000 | 7.86% | 1.14 |
| T3 below average | AZ, CT, IA, ID, MD, ME, ND, NE, NJ, OR, PA, VA, VT, WA, WI, missing | 105,126 | 6.42% | 0.91 |
| T4 low | AK, CA, DC, HI, MA, MN, MT, NH, RI, SD, UT, WY | 122,399 | 4.83% | 0.68 |

State risk may follow regional economic cycles, so the stability of this ranking is tested on the monitoring sample.

## 8. Model scope: loans with a 100% guarantee
- 39,150 development loans (9.0% of the cleaned development sample) have an SBA guarantee equal to the approved amount. They show 4 defaults (0.01%), in every approval year from 1989 to 2002. The 19,784 such loans in the out-of-time sample show practically none, while 31.7% of the other loans default.
- This is treated as a strong data quality warning, not as proof that the default flag is wrong. A possible cause: the SBA repays the full balance when such a loan fails, so the lender records it as paid in full.
- **Decision:** excluded from the model scope as a precaution. The clean table is left unchanged, so the PostgreSQL reconciliation still holds. The filter is applied in `sas/05_model_table.sas`.
- In-scope population: 396,128 development loans (default rate 7.60%) and 370,232 out-of-time loans.
- Sensitivity (`sas/09_scope_sensitivity.sas`): keeping these loans raises Gini by about 0.01 in both samples. No conclusion changes.

## 9. Numeric variables (in-scope development sample)
Method: ten groups of equal size per variable, year-adjusted risk index (`sas/04_numeric_bins.sas`).

| Variable | Finding | Decision |
|---|---|---|
| `loan_amount` | After the scope exclusion the index is flat (0.91 to 1.06). Before it, loans above 170,000 looked about 10% safer. That pattern came from the fully guaranteed loans. | **Excluded.** |
| `guarantee_share` | Standard shares (50%, 75%, 80%, 90%) have an index of 0.92 to 1.02. Some non-standard shares look riskier (1.21 to 1.40) but cover about 3% of loans. The share is set by SBA program rules. | **Excluded.** No consistent relation, and no business rationale for a "non-standard share" flag. |
| `term_months` | 85% of non-defaulted loans have a whole-year term against 9% of defaulted loans. Index from 0.03 (120 months) to 3.87 (1-46 months). | **Excluded.** See section 12. |
| `n_employees` | Index 1.03 (1-6), 0.97 (7-25), 0.91 (26 and more). | Kept in three groups, merged to two in the model (section 10). Missing (3 loans) joins the 1-6 group. |

## 10. Final model
- Logistic regression on the in-scope development sample with approval year as a control variable (`sas/06_model.sas`). A comparison model without year puts sector S2 below S3 (0.39 vs 0.49) and makes the employee effect three times larger, which confirms the year bias.
- Changes after the first fit:
  - `lowdoc` **dropped**: its coefficient turns negative (-0.07) once the other drivers are in, against the univariate result.
  - Employee groups 1-6 and 7-25 **merged**: coefficients 0.081 and 0.067.
- Final drivers: business type, sector group, state group, employees (up to 25 / 26 and more). All coefficients are positive, ordered as expected and significant at 1%.
- Scoring (`sas/07_score.sas`): sum of the driver coefficients, year effects left out. The PD level is set by an intercept fitted on the development sample with the score as offset (-3.519), so the average PD equals 7.60% (through-the-cycle).
- Group indices were rechecked on the in-scope population: the order holds for every variable.

## 11. Validation results
Full tables are in the README.
- Discrimination: Gini 0.168 (95% CI 0.162-0.175) in development and 0.069 (0.065-0.073) out of time, z = 25.1. By vintage: 0.08 to 0.23 in development, 0.11 in 2003, falling to 0.00-0.01 in 2007-2008 (intervals include zero).
- Rank stability out of time: state order broken, business type reversed, sector order kept but compressed, employee effect stronger.
- Calibration: development bands within a ratio of 0.8-1.2 except the lowest band (1.26). By year the ratio moves from 0.29 to 1.84, as expected for a through-the-cycle model. Out of time the ratio is 2.3 to 6.2 by year and 2.8 to 7.5 by band.
- PSI: score 0.036, business type 0.000, employees 0.056, state 0.013, sector 0.244 (expected, NAICS coding change).
- Conclusion: not fit for use. The population is stable but the relationships are not.
- Known limitation: the data has closed loans only, which overstates recent default rates. 25-year loans are 9.9% of in-scope development loans but 2.7% of out-of-time loans. 2003-2004 are the least affected vintages.

## 12. Term field
Tests in `sas/08_term_check.sas`.
- Raw data: 86.6% of paid-in-full loans have a whole-year term against 10.1% of charged-off loans. The pattern is not caused by the cleaning.
- Hypothesis "term = months until charge-off" rejected: only 2.4% of charged-off loans match within one month (2.6% from disbursement). Charge-off can come years after default, so this does not rule out every kind of change.
- Plausibility: in the 2007 vintage, 84-month loans default at 1.1%, 85-119-month loans at 63.7% and 61-77-month loans at 84.8%. Loans with term 0 default at 86% (development) and 98.5% (out-of-time).
- Challenger (final model + term): Gini 0.706 in development and 0.766 out of time. Loans of 1-46 months have about 240 times the default odds of 120-month loans. The first fit failed (SAS: validity questionable) and was fixed by merging term 0 into the shortest group.
- **Decision:** term stays out of the model until the data owner confirms how it is recorded.