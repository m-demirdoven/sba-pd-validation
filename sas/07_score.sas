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


/* =====================================================
   Uncertainty: AUC with 95% confidence intervals.
   ROC with PRED= uses the score as it is, without refitting.
   Gini = 2 * AUC - 1, so its limits are 2 * (AUC limits) - 1.
   ===================================================== */

/* Development and out-of-time samples */
proc sort data=sba.scored_loans out=work.by_sample;
  by sample;
run;

ods select ROCAssociation;
proc logistic data=work.by_sample;
  by sample;
  model default_flag(event='1') = score / nofit;
  roc 'Final model' pred=score;
  ods output ROCAssociation=work.auc_sample;
run;

data work.auc_sample;
  set work.auc_sample;
  gini       = 2 * area - 1;
  gini_lower = 2 * lowerarea - 1;
  gini_upper = 2 * upperarea - 1;
  format area lowerarea upperarea gini gini_lower gini_upper 6.3 stderr 7.4;
run;

proc print data=work.auc_sample noobs;
  var sample area stderr lowerarea upperarea gini gini_lower gini_upper;
run;

/* Is the drop from development to out-of-time larger than chance?
   The two samples are independent: z = difference / sqrt(se1^2 + se2^2) */
data work.auc_test;
  merge work.auc_sample(where=(sample = 'development')
                        rename=(area=auc_dev stderr=se_dev))
        work.auc_sample(where=(sample = 'monitoring')
                        rename=(area=auc_oot stderr=se_oot));
  diff = auc_dev - auc_oot;
  z    = diff / sqrt(se_dev**2 + se_oot**2);
  p    = 2 * (1 - probnorm(abs(z)));
  format auc_dev auc_oot diff 6.3 z 8.2 p pvalue6.4;
run;

proc print data=work.auc_test noobs;
  var auc_dev auc_oot diff z p;
run;

/* Gini with 95% limits by approval year */
proc sort data=sba.scored_loans out=work.by_year;
  by approval_year;
run;

ods select ROCAssociation;
proc logistic data=work.by_year;
  by approval_year;
  model default_flag(event='1') = score / nofit;
  roc 'Final model' pred=score;
  ods output ROCAssociation=work.auc_year;
run;

data work.auc_year;
  set work.auc_year;
  gini       = 2 * area - 1;
  gini_lower = 2 * lowerarea - 1;
  gini_upper = 2 * upperarea - 1;
  format gini gini_lower gini_upper 6.3;
run;

proc print data=work.auc_year noobs;
  var approval_year gini gini_lower gini_upper;
run;



/* =====================================================
   Calibration
   PD = 1 / (1 + exp(-(a + score))). The intercept a is set on the
   development sample so that the average PD equals the development
   default rate: a through-the-cycle level.
   OFFSET keeps the score as it is and estimates only the intercept.
   ===================================================== */
ods select ParameterEstimates;
proc logistic data=sba.scored_loans;
  where sample = 'development';
  model default_flag(event='1') = / offset=score;
  ods output ParameterEstimates=work.calib;
run;

/* PD for every loan */
data sba.scored_pd;
  if _n_ = 1 then set work.calib(keep=estimate rename=(estimate=a));
  set sba.scored_loans;
  pd = 1 / (1 + exp(-(a + score)));
  drop a;
run;

/* Calibration by approval year: predicted vs observed default rate */
proc means data=sba.scored_pd noprint nway;
  class approval_year sample;
  var default_flag pd;
  output out=work.cal_year(drop=_type_ rename=(_freq_=n_loans))
         mean=observed predicted;
run;

data work.cal_year;
  set work.cal_year;
  ratio = observed / predicted;
  format observed predicted percent8.2 ratio 6.2;
run;

proc print data=work.cal_year noobs;
  var approval_year sample n_loans predicted observed ratio;
run;

/* Calibration by PD band. The bands are fixed in advance,
   so the same bands apply to both samples. */
proc format;
  value pd_band
    low  -< 0.04 = 'B1 under 4%'
    0.04 -< 0.06 = 'B2 4-6%'
    0.06 -< 0.08 = 'B3 6-8%'
    0.08 -< 0.10 = 'B4 8-10%'
    0.10 -< 0.12 = 'B5 10-12%'
    0.12 - high  = 'B6 12% and more';
run;

data work.cal_band_in;
  set sba.scored_pd;
  length pd_band $16;
  pd_band = put(pd, pd_band.);
run;

proc means data=work.cal_band_in noprint nway;
  class sample pd_band;
  var default_flag pd;
  output out=work.cal_band(drop=_type_ rename=(_freq_=n_loans))
         mean=observed predicted;
run;

/* z: how many standard errors the observed rate is from the predicted one.
   With large groups even a small gap gives a large z, so the ratio
   is the main measure of the size of the gap. */
data work.cal_band;
  set work.cal_band;
  ratio = observed / predicted;
  z     = (observed - predicted) / sqrt(predicted * (1 - predicted) / n_loans);
  format observed predicted percent8.2 ratio 6.2 z 8.1;
run;

proc print data=work.cal_band noobs;
  by sample;
  var pd_band n_loans predicted observed ratio z;
run;




/* =====================================================
   Population stability (PSI), development vs out-of-time.
   PSI = sum over categories of (oot% - dev%) * ln(oot% / dev%).
   Rule of thumb: under 0.10 stable, 0.10-0.25 moderate shift,
   above 0.25 large shift.
   All variables are stacked into one long table, so one
   PROC FREQ and one MERGE handle them all.
   ===================================================== */
data work.psi_long;
  set work.cal_band_in(keep=sample pd_band business_type sector_grp state_grp emp_grp);
  length variable $13 category $16;
  variable = 'pd_band';       category = pd_band;       output;
  variable = 'business_type'; category = business_type; output;
  variable = 'sector_grp';    category = sector_grp;    output;
  variable = 'state_grp';     category = state_grp;     output;
  /* E1 and E2 are one group in the final model */
  variable = 'emp_grp';
  if emp_grp in ('E1', 'E2') then category = 'E1-E2';
  else category = emp_grp;
  output;
  keep sample variable category;
run;

proc sort data=work.psi_long;
  by variable;
run;

/* OUTPCT adds PCT_ROW: the share of each category within its sample */
proc freq data=work.psi_long noprint;
  by variable;
  tables sample*category / outpct out=work.psi_freq(keep=variable sample category pct_row);
run;

data work.psi_parts;
  merge work.psi_freq(where=(sample = 'development') rename=(pct_row=dev_pct))
        work.psi_freq(where=(sample = 'monitoring')  rename=(pct_row=oot_pct));
  by variable category;
  dev      = dev_pct / 100;
  oot      = oot_pct / 100;
  psi_part = (oot - dev) * log(oot / dev);
  drop sample dev_pct oot_pct;
  format dev oot percent8.1 psi_part 7.4;
run;

proc print data=work.psi_parts noobs;
  by variable;
  var category dev oot psi_part;
run;

proc means data=work.psi_parts noprint nway;
  class variable;
  var psi_part;
  output out=work.psi(drop=_type_ _freq_) sum=psi;
run;

proc print data=work.psi noobs;
  format psi 7.3;
run;