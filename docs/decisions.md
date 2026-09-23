\# Validation Log: Decisions and Findings



\## 1. Data

\- Source: Kaggle, "Should This Loan be Approved or Denied?" (U.S. SBA 7(a) loans, 1962-2014)

\- Raw file: `SBAnational.csv`, 899,164 rows, loaded unchanged into `raw.sba\_loans` (all columns TEXT)



\## 2. Default definition

\- \*\*Default = 1\*\* if `mis\_status = 'CHGOFF'` OR a charge-off date is present

\- \*\*Default = 0\*\* if `mis\_status = 'P I F'` and no charge-off date

\- Loans with missing `mis\_status` (1,997 loans, 0.22%) are excluded

\- Rationale: 4,927 loans are marked paid in full but carry a charge-off date. Consistent with Basel practice, a default that is later cured is still counted as a default ("closed default").

\- Note: the target measures charge-off over the full life of the loan, not default within 12 months. Model output is therefore not directly comparable to a Basel 12-month PD.



\## 3. Sample period

\- \*\*Development sample: 1989-2002\*\*

\- \*\*Out-of-time monitoring sample: 2003-2008\*\*

\- Before 1989 excluded: default rate is 100% up to 1980 and volume jumps from about 2,000 to 13,000 loans in 1989, which points to selection bias (only charged-off loans were kept in older records).

\- After 2008 excluded: recent vintages had not completed their life when the data was extracted (right censoring), so their low default rates are misleading.

\- Default rate rises from about 2% (1993) to 44% (2007), driven by rapid volume growth and the 2008 crisis.



\## 4. Data quality findings

| Field | Finding | Decision |

|---|---|---|

| `mis\_status` | Value is stored as "P I F" (with spaces), not "PIF" | Standardise in clean layer |

| `approvalfy` | 18 loans with value "1976A" | Outside sample period, no impact |

| `chgoffdate` | 47 CHGOFF loans without a date | Keep as default |

| `urbanrural` | Code 0 (undefined) for about 100% of loans before 1999, about 1% after 2000. The field was not collected in early years. | \*\*Excluded from the model.\*\* It would act as a proxy for approval year. |

| `revlinecr` | Only 67% Y/N. Code "0" appears from 1995, peaks at 60% in 1999, falls to about 20% by 2007. Also "T" and keyboard errors. | Keep as Y / N / Unknown. Stability issues expected. |

| `lowdoc` | 0.4% invalid values | Invalid values mapped to Unknown |

| `newexist` | 0.1% coded 0 | Mapped to Unknown |



\## 5. Open items

\- Numeric fields (amounts, term, number of employees, NAICS) not yet checked

