/* =====================================================
   06_model.sas
   PD model on the development sample.
   Approval year enters as a control variable, so the
   coefficients of the risk drivers are measured within
   the same year. A model without year is fitted for
   comparison.
   ===================================================== */

libname sba "~/sba_validation";

/* Model 1: risk drivers + approval year as control.
   PARAM=REF: each coefficient is the difference from the reference group
   (the safest group of each variable). */
ods select ParameterEstimates;
proc logistic data=sba.model_loans;
  where sample = 'development';
  class business_type(ref='Existing') lowdoc(ref='N')
        sector_grp(ref='S4') state_grp(ref='T4') emp_grp(ref='E3')
        approval_year(ref='1989') / param=ref;
  model default_flag(event='1') = business_type lowdoc sector_grp
                                  state_grp emp_grp approval_year;
  ods output ParameterEstimates=work.pe_year;
run;

/* Model 2: same drivers, no year control (for comparison only) */
ods select ParameterEstimates;
proc logistic data=sba.model_loans;
  where sample = 'development';
  class business_type(ref='Existing') lowdoc(ref='N')
        sector_grp(ref='S4') state_grp(ref='T4') emp_grp(ref='E3') / param=ref;
  model default_flag(event='1') = business_type lowdoc sector_grp
                                  state_grp emp_grp;
  ods output ParameterEstimates=work.pe_noyear;
run;

/* Model 3 (final): lowdoc removed, because its sign turns negative once
   the other drivers are in, against the univariate result.
   E1 and E2 merged, because their coefficients are almost equal
   once approval year is controlled (0.081 vs 0.067).
   CLASS uses the formatted value, so the format does the merge. */
proc format;
  value $emp_final
    'E1', 'E2' = 'E1-E2'
    'E3'       = 'E3';
run;

ods select ParameterEstimates Association;
proc logistic data=sba.model_loans;
  where sample = 'development';
  class business_type(ref='Existing') sector_grp(ref='S4') state_grp(ref='T4')
        emp_grp(ref='E3') approval_year(ref='1989') / param=ref;
  format emp_grp $emp_final.;
  model default_flag(event='1') = business_type sector_grp state_grp
                                  emp_grp approval_year;
  /* Saved in the permanent library: needed later for scoring */
  ods output ParameterEstimates=sba.pe_final;
run;