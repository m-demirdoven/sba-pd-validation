/* =====================================================
   09_scope_sensitivity.sas
   Sensitivity to the scope decision: how do the results
   change if the loans with a 100% guarantee are kept?
   Same groupings as 05_model_table.sas and the same score
   as 07_score.sas.
   ===================================================== */

libname sba "~/sba_validation";

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

  /* Final model groups: up to 25 employees vs 26 and more */
  value emp_grp
    ., low-25 = 'E1-E2'
    25<-high  = 'E3';
run;

/* All cleaned loans, including the 100% guarantee loans */
data work.full;
  set sba.clean_loans;
  length sector_grp state_grp $8 emp_grp $5 scope $14;
  sector_grp = put(sector, $sector_grp.);
  state_grp  = put(state, $state_grp.);
  emp_grp    = put(n_employees, emp_grp.);
  if business_type = 'Unknown' then business_type = 'Existing';
  if guarantee_share = 1 then scope = 'Full guarantee';
  else scope = 'In scope';
  score = 0.1968 * (business_type = 'New')
        + 0.8956 * (sector_grp = 'S1')
        + 0.5860 * (sector_grp = 'S2')
        + 0.4565 * (sector_grp = 'S3')
        + 0.7067 * (state_grp = 'T1')
        + 0.5234 * (state_grp = 'T2')
        + 0.2436 * (state_grp = 'T3')
        + 0.0654 * (emp_grp = 'E1-E2');
run;

/* How do the 100% guarantee loans compare on score and default rate? */
proc means data=work.full n mean maxdec=3;
  class sample scope;
  var score default_flag;
run;

/* Gini of the same score on all loans */
proc sort data=work.full;
  by sample;
run;

ods select ROCAssociation;
proc logistic data=work.full;
  by sample;
  model default_flag(event='1') = score / nofit;
  roc 'All loans' pred=score;
  ods output ROCAssociation=work.auc_full;
run;

data work.auc_full;
  set work.auc_full;
  gini       = 2 * area - 1;
  gini_lower = 2 * lowerarea - 1;
  gini_upper = 2 * upperarea - 1;
  format gini gini_lower gini_upper 6.3;
run;

proc print data=work.auc_full noobs;
  var sample gini gini_lower gini_upper;
run;