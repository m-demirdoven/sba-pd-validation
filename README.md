# SBA Small Business Loans: PD Model Development and Validation

Portfolio project on U.S. Small Business Administration (SBA) 7(a) loan data. A probability of default (PD) model is built on loans approved in 1989-2002 and validated on loans approved in 2003-2008. The data preparation was built twice, in PostgreSQL and in SAS, and every figure was reconciled between the two.

## Key findings

1. **A large group of loans has a highly suspicious default record.** 39,150 development loans with a 100% SBA guarantee show 4 defaults (0.01%), and the pattern holds in every approval year. This is a strong data quality warning, not proof that the default flag is wrong. One possible cause is that the SBA repays the full balance when such a loan fails, so the lender records it as paid in full. The loans are excluded from the model scope as a precaution.
2. **The loan term field behaves in a way credit risk cannot explain.** 86.6% of paid-in-full loans have a whole-year term (for example 84 or 120 months), against 10.1% of charged-off loans. In the 2007 vintage, 84-month loans defaulted at 1.1% while 85-119-month loans defaulted at 63.7%. Term is excluded until its recording can be confirmed with the data owner.
3. **Default rates trend strongly over time, which creates false risk drivers.** In the development period the default rate moves from 2.2% (1993) to 13.3% (2001). Variables whose mix changes over time look predictive across years but not within the same year. All variable decisions use a year-adjusted risk index, and approval year is a control variable in the model.
4. **The final model has weak discrimination and does not hold out of time.** Gini is 0.17 on the development sample and 0.07 on the 2003-2008 sample. Within single vintages it falls from about 0.18 to almost zero for 2007-2008. Two drivers changed direction out of time: the regional ranking and the new vs existing business effect. Part of the decline in the latest vintages may come from the data containing closed loans only (see Limitations).
5. **Adding term raises Gini to about 0.69 (development) and 0.75 (out of time)** (provisional figures, see Validation results). This is in line with the very high accuracy reported in other work on this dataset, and shows that such results depend on the term field.

## Data and scope

- Source: Kaggle, "Should This Loan be Approved or Denied?" (Li, Mickel and Taylor, 2018). 899,164 loans approved 1962-2014.
- Default: the loan was charged off, or a charge-off date is present. A default that is later cured still counts. Loans with a missing status (1,997) are excluded.
- Development sample: loans approved 1989-2002. Out-of-time sample: 2003-2008. Earlier years show selection bias (default rate of 100% up to 1980), and later vintages were not complete when the data was extracted.
- The target is charge-off over the life of the loan, not default within 12 months, so the output is not a Basel 12-month PD.

| | Development 1989-2002 | Out-of-time 2003-2008 |
|---|---|---|
| Loans after cleaning | 435,278 | 390,016 |
| Loans with a 100% guarantee (out of scope) | 39,150 | 19,784 |
| Loans in model scope | 396,128 | 370,232 |
| Default rate in scope | 7.60% | 31.7% |

The out-of-time default rate of 31.7% should not be read as the true default rate of the 2003-2008 vintages. The data contains closed loans only, which pushes the observed rate up for recent vintages (see Limitations).

## Approach

- **Data quality:** 11 checks on the raw data (`sql/01_data_quality.sql`, `sas/01_data_quality.sas`). All results match between PostgreSQL and SAS.
- **Year-adjusted risk index:** for each group, observed defaults divided by expected defaults, where expected is the default rate of all loans approved in the same year. An index of 1.0 means average risk for that year. This removes the effect of the strong time trend.
- **Development sample only:** every variable decision is made on the development sample, so the out-of-time test stays clean.
- **Model:** logistic regression with approval year as a control variable, so each coefficient is measured within the same year. The year effects are not used to score loans, because the effect of a future year is not known at approval.

## Variable decisions

| Variable | Decision | Reason |
|---|---|---|
| `business_type` | Kept: New / Existing | New businesses are riskier in all 14 development years |
| `sector` (NAICS) | Kept: 4 groups | Grouped by year-adjusted index. Raw default rates gave a different and misleading order |
| `state` | Kept: 4 groups | Index from 0.58 (MT) to 1.77 (KY, AR) |
| `n_employees` | Kept: up to 25 / 26 and more | Small but consistent effect |
| `lowdoc` | Dropped | Sign turns negative in the model, against the univariate result |
| `revolving` | Dropped | Within the same year, revolving and non-revolving loans have the same default rate. The pooled gap comes from year mix |
| `loan_amount` | Dropped | No pattern once fully guaranteed loans are excluded. The earlier pattern came from those loans |
| `guarantee_share` | Dropped | Set by SBA program rules, no consistent relation with risk |
| `term` | Dropped | See finding 2 and the plausibility check below |
| `urbanrural` | Dropped | Not collected before 2000, acts as a proxy for approval year |
| `disbursementgross` | Dropped | Measures cumulative drawdowns on revolving lines, not loan size |

Full details and figures are in `docs/decisions.md`.

## Final model

Logistic regression on the development sample, approval year as control. Reference groups: Existing, sector S4, state T4, 26 or more employees. All coefficients are significant at 1%, but with almost 400,000 loans even very small effects are significant. The employee effect (odds ratio 1.07) is statistically significant but small in economic terms.

| Variable | Group | Coefficient | Odds ratio |
|---|---|---|---|
| Business type | New | 0.197 | 1.22 |
| Sector | S1 | 0.896 | 2.45 |
| | S2 | 0.586 | 1.80 |
| | S3 | 0.457 | 1.58 |
| State | T1 | 0.707 | 2.03 |
| | T2 | 0.523 | 1.69 |
| | T3 | 0.244 | 1.28 |
| Employees | Up to 25 | 0.065 | 1.07 |

The year control changes the results. Without it, sector S2 ranks below S3 (0.39 vs 0.49), because S2 holds many loans from early, low-default years. The employee effect is also three times larger without it (0.23 vs 0.08).

## Validation results

### Discrimination

| Model | Gini, development | Gini, out-of-time |
|---|---|---|
| Final model (without term) | 0.168 | 0.069 |
| Challenger (final model + term) | 0.690 | 0.752 |

The challenger figures are provisional. SAS reports that the validity of the challenger fit is questionable, most likely because of the small group of loans with a term of 0 months. The model will be refitted with that group merged into the shortest term group.

### Gini by vintage (final model)

| Year | Sample | Loans | Default rate | Gini |
|---|---|---|---|---|
| 1989 | Development | 12,224 | 7.37% | 0.212 |
| 1990 | Development | 13,485 | 5.26% | 0.198 |
| 1991 | Development | 14,332 | 3.33% | 0.077 |
| 1992 | Development | 19,081 | 2.56% | 0.165 |
| 1993 | Development | 21,132 | 2.17% | 0.209 |
| 1994 | Development | 28,424 | 2.59% | 0.191 |
| 1995 | Development | 42,225 | 3.25% | 0.139 |
| 1996 | Development | 34,767 | 4.91% | 0.144 |
| 1997 | Development | 34,669 | 6.65% | 0.183 |
| 1998 | Development | 32,461 | 9.34% | 0.190 |
| 1999 | Development | 33,641 | 11.17% | 0.224 |
| 2000 | Development | 34,272 | 12.63% | 0.207 |
| 2001 | Development | 34,089 | 13.26% | 0.227 |
| 2002 | Development | 41,326 | 12.87% | 0.194 |
| 2003 | Out-of-time | 54,589 | 16.08% | 0.113 |
| 2004 | Out-of-time | 64,548 | 19.90% | 0.109 |
| 2005 | Out-of-time | 73,188 | 27.77% | 0.077 |
| 2006 | Out-of-time | 72,102 | 37.93% | 0.042 |
| 2007 | Out-of-time | 68,365 | 46.07% | 0.006 |
| 2008 | Out-of-time | 37,440 | 44.38% | 0.003 |

The model works at a steady but low level within its own period (average Gini 0.18) and loses its ranking power as the vintages approach the 2008 crisis.

### Rank stability (year-adjusted risk index)

| Driver | Development | Out-of-time | Result |
|---|---|---|---|
| State | T1 1.36, T2 1.15, T3 0.89, T4 0.70 | T1 1.02, T2 1.07, T3 0.87, T4 1.02 | Order broken. The low-risk group (which includes California) became as risky as the high-risk group |
| Business type | New 1.19, Existing 0.92 | New 0.93, Existing 1.03 | Reversed |
| Sector | S1 1.43, S2 1.07, S3 0.94, S4 0.63 | S1 1.15, S2 1.04, S3 1.01, S4 0.85 | Order kept, spread much smaller |
| Employees | 1-6: 1.03, 7-25: 0.97, 26+: 0.91 | 1-6: 1.05, 7-25: 0.89, 26+: 0.62 | Order kept, effect stronger |

### Term plausibility check

Three tests were run on the raw data (`sas/08_term_check.sas`):

1. **Whole-year terms by status:** 86.6% of paid-in-full loans vs 10.1% of charged-off loans. The pattern is in the raw file, not caused by data cleaning.
2. **Is term the number of months until charge-off?** Only 2.4% of charged-off loans match within one month. This explanation is rejected. The mechanism behind the pattern remains unknown.
3. **Default rate by term in the 2007 vintage**, when 46% of loans defaulted:

| Term (months) | Loans | Default rate |
|---|---|---|
| 61-77 | 8,570 | 84.8% |
| 78-83 | 1,186 | 44.4% |
| 84 | 21,711 | 1.1% |
| 85-119 | 3,824 | 63.7% |
| 120 | 2,419 | 1.1% |

A difference of one month in term cannot explain a difference between 1% and 64% in default rate. The field appears to depend on the loan outcome, so a model that uses it would not be usable at approval.

## Limitations

- **Only closed loans are in the data (selection bias).** Loans are either paid in full or charged off, and loans still open when the data was extracted are missing. Defaults close quickly, so recent vintages keep almost all of their defaults but only the good loans that were repaid early. This has two effects. The observed default rate of recent vintages is overstated, and the non-defaulted group is tilted towards short or early-repaid loans, which can distort the ranking tests. The data is consistent with this: loans with a term of 277-300 months (mostly 25-year real estate loans, which cannot be fully repaid by the extraction date unless refinanced) make up 9.9% of in-scope development loans but only 2.7% of out-of-time loans. The out-of-time results, especially for 2005-2008, should be read with this in mind. The 2003-2004 vintages are the least affected.
- **No financial data.** The data has no balance sheet, income or account behaviour, which limits any model built on it.
- **Lifetime target.** The model predicts charge-off over the life of the loan, not a 12-month default.
- **No uncertainty measures yet.** Gini values are point estimates. Confidence intervals are needed before reading small differences, for example between vintages.

## Planned work

1. **Confidence intervals** for AUC and Gini, overall and by vintage.
2. **Calibration:** predicted vs observed default rates by year and by score band. With samples this large, formal tests reject almost any model, so the size of the gap will be judged against practical thresholds, not only p-values.
3. **Population stability (PSI)** of the score and of each driver, development vs out-of-time.
4. **Sensitivity to the scope decision:** model results with the fully guaranteed loans included.
5. **Challenger refit:** resolve the convergence warning of the model with term.
6. **Closed-loans bias:** further tests of how much it affects the out-of-time results.

## Conclusion

The final model is not fit for use as a PD model. Its discrimination is weak within the development period and disappears out of time, because the regional and business type effects changed during the 2008 cycle. The challenger with term shows strong results but should not be used until the data owner confirms how term is recorded.

The main result of the project is the set of data issues found along the way: a highly suspicious default record for fully guaranteed loans, a term field that tracks the outcome, and time effects that create false risk drivers. Each of these would lead to a model that looks strong in testing and fails in use.

**Recommendations**

1. Confirm with the data owner how term and the guarantee share are recorded, and why fully guaranteed loans almost never show a default.
2. Add borrower financial data. The drivers available here carry little information.
3. Treat regional risk as cycle-dependent and review the state groups at every monitoring cycle.
4. Rebuild the samples from data that includes open loans, to remove the bias from closed loans only.

## Repository structure

```
sql/                      PostgreSQL version of the data preparation
  01_data_quality.sql     11 data quality checks
  02_build_clean.sql      clean modelling table
sas/                      SAS version and the full modelling and validation work
  00_import.sas           raw data import
  01_data_quality.sas     data quality checks, reconciled with PostgreSQL
  02_build_clean.sas      clean table, reconciled with PostgreSQL
  03_univariate.sas       categorical variables, year-adjusted risk index
  04_numeric_bins.sas     numeric variables, scope check for 100% guarantee loans
  05_model_table.sas      modelling table with final groupings
  06_model.sas            logistic regression, with and without year control
  07_score.sas            scoring, Gini by sample and vintage, rank stability
  08_term_check.sas       term plausibility tests and challenger model
docs/
  decisions.md            validation log: every decision and the figures behind it
```

## References

- Li, M., Mickel, A. and Taylor, S. (2018). "Should This Loan be Approved or Denied?": A Large Dataset with Class Assignment Guidelines. *Journal of Statistics Education*, 26(1), 55-66.
- Wang, H. and Cheng, L. (2021). CatBoost model with synthetic features in application to loan risk assessment of small businesses. arXiv:2106.07954.
