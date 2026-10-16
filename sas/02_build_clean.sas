/* =====================================================
   02_build_clean.sas
   Build the modelling table by applying the decisions
   documented in docs/decisions.md
   ===================================================== */

libname sba "~/sba_validation";

data sba.clean_loans;
  /* LENGTH before SET fixes the column order and makes
     lowdoc long enough to hold 'Unknown' */
  length loan_id $12 approval_year 8 sample $11 default_flag 8
         loan_amount guarantee_share term_months n_employees 8
         business_type $8 revolving $7 lowdoc $7 sector $7 state $2;
  set sba.raw_loans;
  where not missing(mis_status);

  approval_year = input(substr(approvalfy, 1, 4), 4.);
  if 1989 <= approval_year <= 2008;

  loan_id = loannr_chkdgt;

  /* Sample split */
  if approval_year <= 2002 then sample = 'development';
  else sample = 'monitoring';

  /* Target: charge-off status OR charge-off date present (closed default) */
  default_flag = (mis_status = 'CHGOFF' or not missing(chgoffdate));

  /* Loan size and guarantee share */
  loan_amount     = input(grappv, comma20.);
  guarantee_share = round(input(sba_appv, comma20.) / loan_amount, 0.0001);

  /* Term: 0 is invalid, cap at 300 months */
  term_months = input(term, 8.);
  if term_months = 0 then term_months = .;
  else term_months = min(term_months, 300);

  /* Employees: 9999 is a placeholder code */
  n_employees = input(noemp, 8.);
  if n_employees >= 9999 then n_employees = .;

  /* Categorical fields with Unknown for invalid codes */
  select (newexist);
    when ('1') business_type = 'Existing';
    when ('2') business_type = 'New';
    otherwise  business_type = 'Unknown';
  end;

  if revlinecr in ('Y', 'N') then revolving = revlinecr;
  else revolving = 'Unknown';

  if lowdoc not in ('Y', 'N') then lowdoc = 'Unknown';

  if naics = '0' then sector = 'Unknown';
  else sector = substr(naics, 1, 2);

  /* Excluded: urbanrural (not collected before 2000),
     disbursementgross (cumulative drawdowns on revolvers) */
  keep loan_id approval_year sample default_flag loan_amount guarantee_share
       term_months n_employees business_type revolving lowdoc sector state;
run;

/* Sanity check: size and default rate by sample */
proc sql;
  select sample,
         count(*)                 as n_loans,
         sum(default_flag)        as n_defaults,
         mean(default_flag) * 100 as default_rate_pct format=6.2
  from sba.clean_loans
  group by sample
  order by sample;
quit;