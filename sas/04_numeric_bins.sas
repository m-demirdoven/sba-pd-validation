/* =====================================================
   04_numeric_bins.sas
   Binning of numeric variables, development sample only.
   Same year-adjusted risk index as in 03_univariate.sas.
   Scope: loans with a 100% SBA guarantee are excluded,
   because their default flag is not reliable
   (see docs/decisions.md).
   ===================================================== */

libname sba "~/sba_validation";

/* Scope check: loans with a 100% guarantee have almost no defaults.
   Kept here so the evidence for the exclusion can be reproduced. */
data work.scope_check;
  set sba.clean_loans;
  where sample = 'development';
  full_guarantee = (guarantee_share = 1);
run;

proc freq data=work.scope_check;
  tables full_guarantee*default_flag / nocol nopercent;
run;

/* Development population in scope */
data work.dev;
  set sba.clean_loans;
  where sample = 'development' and guarantee_share < 1;
run;

/* Default rate of each approval year (in-scope loans only) */
proc means data=work.dev noprint nway;
  class approval_year;
  var default_flag;
  output out=work.year_dr(drop=_type_ _freq_) mean=year_dr;
run;

/* Attach the year default rate to every loan */
proc sort data=work.dev;
  by approval_year;
run;

data work.dev;
  merge work.dev work.year_dr;
  by approval_year;
run;

/* Fine classing: split each numeric variable into 10 groups of about equal size.
   Missing values keep a missing rank and show up as their own group. */
proc rank data=work.dev out=work.dev_r groups=10;
  var loan_amount guarantee_share term_months n_employees;
  ranks r_amount r_guarantee r_term r_employees;
run;

/* Loan amount: range, default rate and risk index per group */
proc means data=work.dev_r noprint nway;
  class r_amount / missing;
  var loan_amount default_flag year_dr;
  output out=work.bin_amount(drop=_type_ rename=(_freq_=n_loans))
         min(loan_amount)=min_value max(loan_amount)=max_value
         sum(default_flag year_dr)=observed expected;
run;

data work.bin_amount;
  set work.bin_amount;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2 min_value max_value comma12.;
run;

proc print data=work.bin_amount noobs;
  var r_amount n_loans min_value max_value default_rate risk_index;
run;

/* Guarantee share: range, default rate and risk index per group */
proc means data=work.dev_r noprint nway;
  class r_guarantee / missing;
  var guarantee_share default_flag year_dr;
  output out=work.bin_guarantee(drop=_type_ rename=(_freq_=n_loans))
         min(guarantee_share)=min_value max(guarantee_share)=max_value
         sum(default_flag year_dr)=observed expected;
run;

data work.bin_guarantee;
  set work.bin_guarantee;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2 min_value max_value percent8.1;
run;

proc print data=work.bin_guarantee noobs;
  var r_guarantee n_loans min_value max_value default_rate risk_index;
run;


/* Term in months: range, default rate and risk index per group.
   Term 0 was set to missing in the clean table and shows up as its own group. */
proc means data=work.dev_r noprint nway;
  class r_term / missing;
  var term_months default_flag year_dr;
  output out=work.bin_term(drop=_type_ rename=(_freq_=n_loans))
         min(term_months)=min_value max(term_months)=max_value
         sum(default_flag year_dr)=observed expected;
run;

data work.bin_term;
  set work.bin_term;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc print data=work.bin_term noobs;
  var r_term n_loans min_value max_value default_rate risk_index;
run;

/* Leakage check for term. If term were fixed at approval, defaulted and
   non-defaulted loans would have a similar share of whole-year terms
   (multiples of 12 months, e.g. 84 or 120). */
data work.term_check;
  set work.dev;
  length term_type $11;
  if missing(term_months) then term_type = 'Missing';
  else if mod(term_months, 12) = 0 then term_type = 'Whole years';
  else term_type = 'Other';
run;

/* NOROW NOPERCENT: show column percents, i.e. the mix of term types
   among non-defaulted (0) and defaulted (1) loans */
proc freq data=work.term_check;
  tables term_type*default_flag / norow nopercent;
run;

/* Number of employees: range, default rate and risk index per group.
   Code 9999 was set to missing in the clean table. Many ties
   (1, 2, 3 employees), so fewer than 10 groups may appear. */
proc means data=work.dev_r noprint nway;
  class r_employees / missing;
  var n_employees default_flag year_dr;
  output out=work.bin_employees(drop=_type_ rename=(_freq_=n_loans))
         min(n_employees)=min_value max(n_employees)=max_value
         sum(default_flag year_dr)=observed expected;
run;

data work.bin_employees;
  set work.bin_employees;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc print data=work.bin_employees noobs;
  var r_employees n_loans min_value max_value default_rate risk_index;
run;

