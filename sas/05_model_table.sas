
/* =====================================================
   05_model_table.sas
   Build the modelling table: in-scope loans with the
   groupings decided in 03_univariate.sas and
   04_numeric_bins.sas (development sample only).
   ===================================================== */

libname sba "~/sba_validation";

/* Groupings. OTHER catches codes that never appeared in the
   development sample, so they are visible in the checks below. */
proc format;
  value $sector_grp
    '45'                                    = 'S1'
    '11','48','31','44','71','53','72','32',
    '49','51','Unknown'                     = 'S2'
    '23','81','56','42','33','61'           = 'S3'
    '21','54','92','62','22','52','55'      = 'S4'
    other                                   = 'Unmapped';

  value $state_grp
    'KY','AR','LA','WV','SC','TX','OK','MS','TN','IL','AL'      = 'T1'
    'MI','NY','MO','FL','GA','OH','IN','KS','NC','CO','NM',
    'NV','DE'                                                   = 'T2'
    'NJ','PA','CT','ID','ND','NE','WI','ME','IA','OR','VA',
    'MD','AZ','VT','WA',' '                                     = 'T3'
    'HI','UT','DC','MN','AK','MA','CA','SD','RI','WY','NH','MT' = 'T4'
    other                                                       = 'Unmapped';

  /* Missing employees join E1, the most common group */
  value emp_grp
    ., low-6  = 'E1'
    6<-25     = 'E2'
    25<-high  = 'E3';
run;

/* Modelling table, both samples.
   Scope: loans with a 100% guarantee are excluded. */
data sba.model_loans;
  set sba.clean_loans;
  where guarantee_share < 1;

  length sector_grp state_grp $8 emp_grp $2;
  sector_grp = put(sector, $sector_grp.);
  state_grp  = put(state, $state_grp.);
  emp_grp    = put(n_employees, emp_grp.);

  /* Small Unknown groups merged into the largest group */
  if business_type = 'Unknown' then business_type = 'Existing';
  if lowdoc = 'Unknown' then lowdoc = 'N';

  keep loan_id approval_year sample default_flag
       business_type lowdoc sector_grp state_grp emp_grp;
run;

/* Checks: size of each sample, and no Unmapped values */
proc freq data=sba.model_loans;
  tables sample business_type lowdoc sector_grp state_grp emp_grp / missing;
run;


/* Re-check the groups on the in-scope development sample.
   The groups were set before the 100% guarantee loans were excluded,
   so the risk index of each group is recomputed here.
   Expected order: S1 > S2 > S3 > S4, T1 > T2 > T3 > T4, E1 > E2 > E3,
   New > Existing, lowdoc Y > N. */
proc means data=sba.model_loans noprint nway;
  where sample = 'development';
  class approval_year;
  var default_flag;
  output out=work.year_dr(drop=_type_ _freq_) mean=year_dr;
run;

proc sort data=sba.model_loans(where=(sample = 'development')) out=work.dev;
  by approval_year;
run;

data work.dev;
  merge work.dev work.year_dr;
  by approval_year;
run;

/* WAYS 1: one block of rows per variable */
proc means data=work.dev noprint;
  class business_type lowdoc sector_grp state_grp emp_grp;
  ways 1;
  var default_flag year_dr;
  output out=work.grp_check(rename=(_freq_=n_loans)) sum=observed expected;
run;

data work.grp_check;
  set work.grp_check;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc print data=work.grp_check noobs;
  var business_type lowdoc sector_grp state_grp emp_grp n_loans default_rate risk_index;
run;
