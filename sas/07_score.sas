/* =====================================================
   07_score.sas
   Score all in-scope loans with the final model and test
   discrimination on both samples.
   The year coefficients are left out: the year effect of
   a future year is not known when a loan is approved.
   ===================================================== */

libname sba "~/sba_validation";

/* Risk score = sum of the risk driver coefficients from 06_model.sas.
   Reference groups (Existing, S4, T4, E3) add 0.
   A comparison returns 1 or 0, so each term adds its coefficient
   only when the loan is in that group. */
data sba.scored_loans;
  set sba.model_loans;
  score = 0.1968 * (business_type = 'New')
        + 0.8956 * (sector_grp = 'S1')
        + 0.5860 * (sector_grp = 'S2')
        + 0.4565 * (sector_grp = 'S3')
        + 0.7067 * (state_grp = 'T1')
        + 0.5234 * (state_grp = 'T2')
        + 0.2436 * (state_grp = 'T3')
        + 0.0654 * (emp_grp in ('E1', 'E2'));
run;

/* Discrimination of the score alone. c = AUC, Somers' D = Gini. */

/* Development sample (in-sample) */
ods select Association;
proc logistic data=sba.scored_loans;
  where sample = 'development';
  model default_flag(event='1') = score;
run;

/* Monitoring sample (out-of-time, 2003-2008) */
ods select Association;
proc logistic data=sba.scored_loans;
  where sample = 'monitoring';
  model default_flag(event='1') = score;
run;

/* Gini by approval year: ranking within each vintage,
   free of the year mix */
proc sort data=sba.scored_loans out=work.by_year;
  by approval_year;
run;

ods select Association;
proc logistic data=work.by_year;
  by approval_year;
  model default_flag(event='1') = score;
  ods output Association=work.assoc_year;
run;

/* Keep only the Gini (Somers' D) row of each year */
data work.gini_year;
  set work.assoc_year;
  where label2 = "Somers' D";
  gini = nvalue2;
  keep approval_year gini;
run;

/* Add sample, number of loans and default rate per year */
proc means data=work.by_year noprint nway;
  class approval_year sample;
  var default_flag;
  output out=work.dr_year(drop=_type_ rename=(_freq_=n_loans)) mean=default_rate;
run;

data work.gini_year;
  merge work.dr_year work.gini_year;
  by approval_year;
  format default_rate percent8.2 gini 6.3;
run;

proc print data=work.gini_year noobs;
  var approval_year sample n_loans default_rate gini;
run;

/* Rank stability: do the groups keep their order in the monitoring sample?
   Same year-adjusted risk index, using monitoring years only.
   Development indices for comparison:
   S1 1.43, S2 1.07, S3 0.94, S4 0.63 | T1 1.36, T2 1.15, T3 0.89, T4 0.70
   New 1.19, Existing 0.92 | E1 1.03, E2 0.97, E3 0.91 */
proc means data=sba.scored_loans noprint nway;
  where sample = 'monitoring';
  class approval_year;
  var default_flag;
  output out=work.year_dr_mon(drop=_type_ _freq_) mean=year_dr;
run;

proc sort data=sba.scored_loans(where=(sample = 'monitoring')) out=work.mon;
  by approval_year;
run;

data work.mon;
  merge work.mon work.year_dr_mon;
  by approval_year;
run;

proc means data=work.mon noprint;
  class business_type sector_grp state_grp emp_grp;
  ways 1;
  var default_flag year_dr;
  output out=work.rank_mon(rename=(_freq_=n_loans)) sum=observed expected;
run;

data work.rank_mon;
  set work.rank_mon;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc print data=work.rank_mon noobs;
  var business_type sector_grp state_grp emp_grp n_loans default_rate risk_index;
run;