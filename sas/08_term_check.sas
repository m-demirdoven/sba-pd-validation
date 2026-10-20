/* =====================================================
   08_term_check.sas
   Is the term field changed after default?
   Run on the raw table, so no cleaning step can cause it.
   ===================================================== */

libname sba "~/sba_validation";

/* Test 1: share of whole-year terms by loan status, raw data */
data work.term_raw;
  set sba.raw_loans;
  where mis_status in ('CHGOFF', 'P I F');
  term_n     = input(term, 8.);
  whole_year = (term_n > 0 and mod(term_n, 12) = 0);
run;

proc freq data=work.term_raw;
  tables whole_year*mis_status / norow nopercent;
run;

/* Test 2: for charged-off loans, does the recorded term equal the
   months between approval (or disbursement) and charge-off? */
data work.term_test;
  set sba.raw_loans;
  where mis_status = 'CHGOFF';
  term_n      = input(term, 8.);
  appr_dt     = input(approvaldate, ?? anydtdte11.);
  disb_dt     = input(disbursementdate, ?? anydtdte11.);
  chgoff_dt   = input(chgoffdate, ?? anydtdte11.);
  m_from_appr = intck('month', appr_dt, chgoff_dt);
  m_from_disb = intck('month', disb_dt, chgoff_dt);
  /* SAS treats a missing value as smaller than any number,
     so the match is only computed when both values exist */
  if n(term_n, m_from_appr) = 2 then match_appr = (abs(term_n - m_from_appr) <= 1);
  if n(term_n, m_from_disb) = 2 then match_disb = (abs(term_n - m_from_disb) <= 1);
  format appr_dt disb_dt chgoff_dt date9.;
run;

/* Share of charged-off loans where term = months to charge-off (within 1 month) */
proc means data=work.term_test n mean maxdec=3;
  var match_appr match_disb;
run;

/* First 20 charged-off loans, to look at by eye */
proc print data=work.term_test(obs=20) noobs;
  var term_n appr_dt disb_dt chgoff_dt m_from_appr m_from_disb;
run;

/* =====================================================
   Sensitivity: challenger model = final model + term.
   Term enters with the fine classes from 04_numeric_bins.sas.
   ===================================================== */

proc format;
  value term_grp
      /* Term 0 (missing) merged into the shortest group: the small separate
       group made the challenger fit fail (SAS: validity questionable) */
    ., low-46 = '001-046'
    46<-60    = '047-060'
    60<-77    = '061-077'
    77<-83    = '078-083'
    83<-84    = '084'
    84<-119   = '085-119'
    119<-120  = '120'
    120<-180  = '121-180'
    180<-276  = '181-276'
    276<-high = '277-300';

  /* Same merge of E1 and E2 as in the final model */
  value $emp_final
    'E1', 'E2' = 'E1-E2'
    'E3'       = 'E3';
run;

/* Bring term into the scored table. MERGE needs both tables sorted by loan id. */
proc sort data=sba.scored_loans out=work.scored;
  by loan_id;
run;

proc sort data=sba.clean_loans(keep=loan_id term_months) out=work.term;
  by loan_id;
run;

data work.challenger;
  merge work.scored(in=in_model) work.term;
  by loan_id;
  if in_model;
  length term_grp $7;
  term_grp = put(term_months, term_grp.);
run;

/* Challenger fitted on the development sample, year as control.
   OUTMODEL saves the fitted model so it can score other data. */
ods select ParameterEstimates;
proc logistic data=work.challenger outmodel=work.challenger_model;
  where sample = 'development';
  class business_type(ref='Existing') sector_grp(ref='S4') state_grp(ref='T4')
        emp_grp(ref='E3') term_grp(ref='120') approval_year(ref='1989') / param=ref;
  format emp_grp $emp_final.;
  model default_flag(event='1') = business_type sector_grp state_grp emp_grp
                                  term_grp approval_year;
run;

/* Score all loans with the year set to the reference year 1989,
   so the year effect is zero for everyone, as in 07_score.sas */
data work.to_score;
  set work.challenger;
  approval_year = 1989;
  format emp_grp $emp_final.;
run;

proc logistic inmodel=work.challenger_model;
  score data=work.to_score out=work.challenger_scored;
run;

/* Gini of the challenger. P_1 = predicted probability of default. */
ods select Association;
proc logistic data=work.challenger_scored;
  where sample = 'development';
  model default_flag(event='1') = p_1;
run;

ods select Association;
proc logistic data=work.challenger_scored;
  where sample = 'monitoring';
  model default_flag(event='1') = p_1;
run;

/* Plausibility check: default rate by term group in each sample,
   and in the 2007 vintage, the worst year of the crisis.
   A genuine risk driver would not keep some groups near 0%
   when almost half of the vintage defaults. */
proc tabulate data=work.challenger;
  class term_grp sample;
  var default_flag;
  table term_grp, sample*default_flag*(n*f=comma8. mean*f=percent8.2);
run;

proc tabulate data=work.challenger;
  where approval_year = 2007;
  class term_grp;
  var default_flag;
  table term_grp, default_flag*(n*f=comma8. mean*f=percent8.2);
run;