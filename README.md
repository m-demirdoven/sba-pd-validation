# SBA Small Business Loans: PD Model Development and Validation

Portfolio project on U.S. Small Business Administration (SBA) 7(a) loan data. A probability of default (PD) model is built on loans approved in 1989-2002 and validated on loans approved in 2003-2008. The data preparation was built twice, in PostgreSQL and in SAS, and every figure was reconciled between the two.

## Key findings

1. **A large group of loans has a highly suspicious default record.** 39,150 development loans with a 100% SBA guarantee show 4 defaults (0.01%), and the pattern holds in every approval year. The 19,784 such loans in the out-of-time sample show practically no defaults either (under 0.05%), while 31.7% of the other loans default. This is a strong data quality warning, not proof that the default flag is wrong. One possible cause is that the SBA repays the full balance when such a loan fails, so the lender records it as paid in full. The loans are excluded from the model scope as a precaution.
2. **The loan term field behaves in a way credit risk cannot explain.** 86.6% of paid-in-full loans have a whole-year term (for example 84 or 120 months), against 10.1% of charged-off loans. In the 2007 vintage, 84-month loans defaulted at 1.1% while 85-119-month loans defaulted at 63.7%. Term is excluded until its recording can be confirmed with the data owner.
3. **Default rates trend strongly over time, which creates false risk drivers.** In the development period the default rate moves from 2.2% (1993) to 13.3% (2001). Variables whose mix changes over time look predictive across years but not within the same year. All variable decisions use a year-adjusted risk index, and approval year is a control variable in the model.
4. **The final model has weak discrimination and does not hold out of time.** Gini is 0.17 (95% CI 0.16-0.18) on the development sample and 0.07 (0.07-0.07) on the 2003-2008 sample. The drop is far larger than sampling noise (z = 25). Within single vintages Gini falls from about 0.18 to a level not distinguishable from zero for 2007-2008. Two drivers changed direction out of time: the regional ranking and the new vs existing business effect. The decline already shows in 2003-2004, the vintages least affected by the closed-loans bias (see Limitations), so it is not only a data artefact. The predicted default level is also far too low out of time: observed rates are 2.3 to 6.2 times the predicted ones. The borrower mix barely changed (PSI of the score 0.04), so the failure comes from changed relationships between the drivers and default, not from a different population.
5. **Adding term raises Gini to 0.71 (development) and 0.77 (out of time).** This is in line with the very high accuracy reported in other work on this dataset, and shows that such results depend on the term field.

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

| Model | Gini, development (95% CI) | Gini, out-of-time (95% CI) |
|---|---|---|
| Final model (without term) | 0.168 (0.162-0.175) | 0.069 (0.065-0.073) |
| Challenger (final model + term) | 0.706 | 0.766 |

Confidence intervals come from the standard error of the AUC (SAS PROC LOGISTIC, ROC statement), converted with Gini = 2 x AUC - 1. The two samples are independent, so the drop from development to out-of-time is tested with z = difference / sqrt(se1² + se2²): AUC 0.584 vs 0.534, z = 25.1, p < 0.0001.

Statistical and economic significance point the same way here, but they are not the same thing. The development Gini of 0.17 is clearly different from zero in a statistical sense, yet it is far below the 0.40-0.60 range usually expected from an SME application model, so in economic terms the model ranks risk only weakly.

The first fit of the challenger did not converge properly (SAS reported that the validity of the fit was questionable, with implausibly small standard errors). The cause was the small group of loans with a term of 0 months. That group was merged into the shortest term group and the model was refitted without warnings. In the refitted challenger, loans with a term of 1-46 months have about 240 times the default odds of 120-month loans (coefficient 5.49), an effect far larger than any credit risk driver would plausibly have.

### Gini by vintage (final model)

| Year | Sample | Loans | Default rate | Gini | 95% CI |
|---|---|---|---|---|---|
| 1989 | Development | 12,224 | 7.37% | 0.212 | 0.175-0.250 |
| 1990 | Development | 13,485 | 5.26% | 0.198 | 0.156-0.240 |
| 1991 | Development | 14,332 | 3.33% | 0.077 | 0.024-0.131 |
| 1992 | Development | 19,081 | 2.56% | 0.165 | 0.115-0.215 |
| 1993 | Development | 21,132 | 2.17% | 0.209 | 0.159-0.259 |
| 1994 | Development | 28,424 | 2.59% | 0.191 | 0.150-0.231 |
| 1995 | Development | 42,225 | 3.25% | 0.139 | 0.108-0.170 |
| 1996 | Development | 34,767 | 4.91% | 0.144 | 0.118-0.171 |
| 1997 | Development | 34,669 | 6.65% | 0.183 | 0.161-0.206 |
| 1998 | Development | 32,461 | 9.34% | 0.190 | 0.169-0.210 |
| 1999 | Development | 33,641 | 11.17% | 0.224 | 0.205-0.243 |
| 2000 | Development | 34,272 | 12.63% | 0.207 | 0.189-0.225 |
| 2001 | Development | 34,089 | 13.26% | 0.227 | 0.209-0.244 |
| 2002 | Development | 41,326 | 12.87% | 0.194 | 0.177-0.210 |
| 2003 | Out-of-time | 54,589 | 16.08% | 0.113 | 0.100-0.126 |
| 2004 | Out-of-time | 64,548 | 19.90% | 0.109 | 0.098-0.120 |
| 2005 | Out-of-time | 73,188 | 27.77% | 0.077 | 0.068-0.086 |
| 2006 | Out-of-time | 72,102 | 37.93% | 0.042 | 0.033-0.051 |
| 2007 | Out-of-time | 68,365 | 46.07% | 0.006 | -0.003-0.015 |
| 2008 | Out-of-time | 37,440 | 44.38% | 0.003 | -0.009-0.014 |

The model works at a steady but low level within its own period (average Gini 0.18) and loses its ranking power as the vintages approach the 2008 crisis. The intervals help to separate signal from noise:

- Early development years have wide intervals because they have few defaults (1993: 2.2% of 21,132 loans). The low value for 1991 is partly noise, but its interval still lies below those of every development year except 1992, 1995 and 1996.
- 2003 and 2004 are the out-of-time vintages least affected by the closed-loans bias. Their Gini of about 0.11 is lower than in every development year except 1991, and their intervals lie below those of ten of the fourteen development years. The decline starts before the crisis vintages.
- For 2007 and 2008 the intervals include zero: the model does not rank these loans better than chance.

Comparing overlapping intervals is a conservative check, not a formal test of each pair of years.

### Calibration

The score has no level of its own. The intercept is set on the development sample so that the average PD equals the development default rate of 7.60%, a through-the-cycle level (logistic regression with the score as an offset, intercept -3.519). The model therefore predicts about 7-8% in every year, and the question is how far the observed rates move away from that.

As a practical tolerance, this project treats a ratio of observed to predicted between 0.8 and 1.2 as acceptable. This is a project choice, not a regulatory threshold. With around 100,000 loans per band, even small gaps are statistically significant, so the ratio is used to judge the size of a gap and the z-value only to show whether it could be noise.

**By PD band**

| PD band | Development: predicted | observed | ratio | z | Out-of-time: predicted | observed | ratio |
|---|---|---|---|---|---|---|---|
| Under 4% | 3.44% | 4.33% | 1.26 | 6.9 | 3.47% | 26.06% | 7.52 |
| 4-6% | 5.27% | 5.57% | 1.06 | 4.4 | 5.28% | 30.30% | 5.73 |
| 6-8% | 6.86% | 7.15% | 1.04 | 3.4 | 7.04% | 31.23% | 4.43 |
| 8-10% | 8.74% | 8.41% | 0.96 | -3.6 | 8.85% | 33.52% | 3.79 |
| 10-12% | 10.51% | 9.75% | 0.93 | -6.1 | 10.62% | 35.09% | 3.30 |
| 12% and more | 12.78% | 12.77% | 1.00 | -0.1 | 13.08% | 37.15% | 2.84 |

- **Development:** observed rates rise steadily from the lowest to the highest band, and five of six bands are within the tolerance. Only the lowest band is under-predicted (ratio 1.26). In the first five bands the z-values of 3 to 7 show that the gaps are not noise, but apart from the lowest band they are all below 0.8 percentage points, which is small in practice.
- **Out-of-time:** every band fails, with observed rates 2.8 to 7.5 times the prediction. Observed rates still rise from the lowest to the highest band (26% to 37%), so some ranking remains, but the spread is much flatter: the highest band defaults 1.4 times as often as the lowest, against 2.9 times in development.

**By vintage**

| Year | Predicted | Observed | Ratio | | Year | Predicted | Observed | Ratio |
|---|---|---|---|---|---|---|---|---|
| 1989 | 7.68% | 7.37% | 0.96 | | 1999 | 7.65% | 11.17% | 1.46 |
| 1990 | 7.58% | 5.26% | 0.69 | | 2000 | 7.62% | 12.63% | 1.66 |
| 1991 | 7.53% | 3.33% | 0.44 | | 2001 | 7.22% | 13.26% | 1.84 |
| 1992 | 7.53% | 2.56% | 0.34 | | 2002 | 7.08% | 12.87% | 1.82 |
| 1993 | 7.59% | 2.17% | 0.29 | | 2003 | 6.98% | 16.08% | 2.30 |
| 1994 | 7.80% | 2.59% | 0.33 | | 2004 | 7.05% | 19.90% | 2.82 |
| 1995 | 7.90% | 3.25% | 0.41 | | 2005 | 7.39% | 27.77% | 3.76 |
| 1996 | 7.80% | 4.91% | 0.63 | | 2006 | 7.45% | 37.93% | 5.09 |
| 1997 | 7.72% | 6.65% | 0.86 | | 2007 | 7.39% | 46.07% | 6.23 |
| 1998 | 7.73% | 9.34% | 1.21 | | 2008 | 7.39% | 44.38% | 6.01 |

- Within the development period the ratio moves between 0.29 (1993) and 1.84 (2001). This is what a through-the-cycle model is expected to do: it holds a long-run level while yearly default rates swing with the economy. For a point-in-time use such as IFRS 9, the model would need an adjustment for economic conditions.
- Out of time the ratio reaches 2.3 already in 2003, beyond the largest gap seen in development, and rises to 6.2 in 2007. Part of this comes from the closed-loans bias, which inflates observed rates in recent vintages, and part from the crisis. The data cannot separate the two, but 2003 is the least affected vintage and is already outside the development range.

### Sensitivity to the scope decision

The same score was applied to all cleaned loans, including those with a 100% guarantee (`sas/09_scope_sensitivity.sas`).

| Sample | Group | Loans | Average score | Default rate |
|---|---|---|---|---|
| Development | 100% guarantee | 39,150 | 0.888 | 0.0% |
| | In scope | 396,128 | 0.969 | 7.6% |
| Out-of-time | 100% guarantee | 19,784 | 0.826 | 0.0% |
| | In scope | 370,232 | 0.918 | 31.7% |

| Gini | In scope only | All loans |
|---|---|---|
| Development | 0.168 (0.162-0.175) | 0.180 (0.173-0.186) |
| Out-of-time | 0.069 (0.065-0.073) | 0.077 (0.073-0.081) |

Keeping the fully guaranteed loans would make the model look slightly better, because these loans never default and happen to score a little below average. The gain (about 0.01 Gini) comes from the suspicious records, not from better ranking of real borrowers. It does not change any conclusion: the model stays weak in development and fails out of time. Keeping them would also lower the development default rate from 7.60% to 6.92% and with it the calibrated PD level.

### Population stability (PSI)

PSI compares the distribution of each variable between the development and out-of-time samples: the sum over categories of (out-of-time share - development share) x ln(out-of-time share / development share). A common rule of thumb reads values below 0.10 as stable, 0.10-0.25 as a moderate shift and above 0.25 as a large shift.

| Variable | PSI | Reading |
|---|---|---|
| Score (PD band) | 0.036 | Stable |
| Business type | 0.000 | Stable |
| Employees | 0.056 | Stable |
| State group | 0.013 | Stable |
| Sector group | 0.244 | Moderate, close to large |

The sector shift was expected (see `docs/decisions.md`, section 5). Group S2 holds the loans with a missing NAICS code, which exist almost only before 2001, so its share falls from 62.1% to 37.8%, while S3 rises from 22.4% to 37.6%. This is a change in data recording, not in the borrowers. It has little effect on the score, because S2 and S3 have similar coefficients (0.586 and 0.457).

The main message is the contrast with the earlier results: the population is stable, but the relationships are not. Discrimination falls, calibration fails and two drivers change direction, while the mix of borrowers stays almost the same. Monitoring based on PSI alone would have missed the problem.

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
## Further work

- **Closed-loans bias:** this data cannot separate the effect of the bias from the effect of the 2008 crisis. A clean out-of-time test needs a source that includes loans still open at extraction, such as the SBA 7(a) FOIA files.

## Conclusion

The final model is not fit for use as a PD model. Its discrimination is weak within the development period and disappears out of time, because the regional and business type effects changed during the 2008 cycle. Its calibration holds in development but fails badly out of time, while the borrower mix stays stable, so standard PSI monitoring would not have raised an alarm. The challenger with term shows strong results but should not be used until the data owner confirms how term is recorded.

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
  07_score.sas            scoring, Gini with confidence intervals, rank stability,
                          calibration, PSI
  08_term_check.sas       term plausibility tests and challenger model
  09_scope_sensitivity.sas  results with the 100% guarantee loans included
docs/
  decisions.md            validation log: every decision and the figures behind it
```

## References

- Li, M., Mickel, A. and Taylor, S. (2018). "Should This Loan be Approved or Denied?": A Large Dataset with Class Assignment Guidelines. *Journal of Statistics Education*, 26(1), 55-66.
- Wang, H. and Cheng, L. (2021). CatBoost model with synthetic features in application to loan risk assessment of small businesses. arXiv:2106.07954.
