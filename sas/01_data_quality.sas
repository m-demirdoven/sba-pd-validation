/* =====================================================
   01_data_quality.sas
   Data quality checks on raw SBA loan data
   ===================================================== */

libname sba "~/sba_validation";

/* 1. Target variable distribution (MISSING option shows blank status too) */
proc freq data=sba.raw_loans;
  tables mis_status / missing;
run;

/* 2. Consistency between loan status and charge-off date
   Expectation: CHGOFF loans have a charge-off date, PIF loans do not */
proc sql;
  select mis_status,
         case when missing(chgoffdate) then 'no_date'
              else 'has_date'
         end as chgoff_date_flag,
         count(*) as n_loans
  from sba.raw_loans
  group by mis_status, chgoff_date_flag
  order by mis_status, chgoff_date_flag;
quit;


/* 3. Approval fiscal year: values that are not a valid 4-digit year */
proc sql;
  select approvalfy,
         count(*) as n_loans
  from sba.raw_loans
  where missing(approvalfy)
     or prxmatch('/^[0-9]{4}$/', strip(approvalfy)) = 0
  group by approvalfy
  order by n_loans desc;
quit;

/* 4. Loan volume and default rate by approval year
   Default: CHGOFF status OR charge-off date present
   Loans with missing status are excluded */
proc sql;
  select input(substr(approvalfy, 1, 4), 4.) as approval_year,
         count(*) as n_loans,
         mean(case when mis_status = 'CHGOFF'
                     or not missing(chgoffdate) then 1
                   else 0 end) * 100 as default_rate_pct format=6.2
  from sba.raw_loans
  where not missing(mis_status)
  group by approval_year
  order by approval_year;
quit;

/* Population for checks 5-11: approval years 1989-2008, known status.
   PROC SQL has no WITH clause, so the population is built once here.
   WHERE filters on columns read from the input table; approval_year is
   created inside this step, so a subsetting IF is used for it. */
data work.pop;
  set sba.raw_loans;
  where not missing(mis_status);
  approval_year = input(substr(approvalfy, 1, 4), 4.);
  if 1989 <= approval_year <= 2008;
  default_flag = (mis_status = 'CHGOFF' or not missing(chgoffdate));
run;

/* 5. Categorical fields: value distribution */
proc freq data=work.pop;
  tables newexist urbanrural revlinecr lowdoc / missing;
run;


/* 6. Coding changes over time: share of suspicious codes by approval year.
   In SAS a comparison returns 1 or 0, so MEAN(revlinecr = '0') gives the
   share directly (same as AVG(CASE WHEN ... THEN 1 ELSE 0 END) in PostgreSQL). */
proc sql;
  select approval_year,
         count(*) as n_loans,
         mean(revlinecr = '0')  * 100 as revlinecr_zero_pct  format=5.1,
         mean(revlinecr = 'T')  * 100 as revlinecr_t_pct     format=5.1,
         mean(urbanrural = '0') * 100 as urbanrural_zero_pct format=5.1
  from work.pop
  group by approval_year
  order by approval_year;
quit;


/* 7. Numeric fields: values that do not match the expected format.
   STRIP removes the blanks SAS adds to fill character columns,
   so the pattern can end with $ like in PostgreSQL. */
proc sql;
  select count(*) as n_loans,
         sum(prxmatch('/^\$[0-9,]+\.[0-9]{2}$/', strip(grappv)) = 0)            as bad_grappv,
         sum(prxmatch('/^\$[0-9,]+\.[0-9]{2}$/', strip(sba_appv)) = 0)          as bad_sba_appv,
         sum(prxmatch('/^\$[0-9,]+\.[0-9]{2}$/', strip(disbursementgross)) = 0) as bad_disbursement,
         sum(prxmatch('/^[0-9]+$/', strip(term))  = 0) as bad_term,
         sum(prxmatch('/^[0-9]+$/', strip(noemp)) = 0) as bad_noemp,
         sum(prxmatch('/^[0-9]+$/', strip(naics)) = 0) as bad_naics
  from work.pop;
quit;








/* 8. Numeric fields: range and distribution.
   The COMMA informat reads "$1,234.00" as 1234 (it drops $ and commas). */
data work.pop_num;
  set work.pop;
  grappv_n       = input(grappv, comma20.);
  sba_appv_n     = input(sba_appv, comma20.);
  disbursement_n = input(disbursementgross, comma20.);
  term_n         = input(term, 8.);
  noemp_n        = input(noemp, 8.);
  keep approval_year default_flag revlinecr naics
       grappv_n sba_appv_n disbursement_n term_n noemp_n;
run;

proc means data=work.pop_num n min p1 median p99 max maxdec=0;
  var grappv_n sba_appv_n disbursement_n term_n noemp_n;
run;

proc sql;
  select sum(grappv_n = 0)       as zero_grappv,
         sum(sba_appv_n = 0)     as zero_sba_appv,
         sum(disbursement_n = 0) as zero_disbursement,
         sum(term_n = 0)         as zero_term,
         sum(noemp_n = 0)        as zero_noemp
  from work.pop_num;
quit;


/* 9. Numeric anomalies, split by revolving line flag */
proc sql;
  select case when revlinecr in ('Y', 'N') then revlinecr
              else 'Unknown'
         end as revline_group,
         count(*) as n_loans,
         sum(disbursement_n > grappv_n)         as disb_above_approved,
         mean(disbursement_n > grappv_n) * 100  as disb_above_approved_pct format=5.1,
         sum(sba_appv_n > grappv_n)             as guarantee_above_approved,
         sum(term_n = 0)                        as term_zero,
         sum(term_n > 300)                      as term_above_300,
         sum(noemp_n = 0)                       as noemp_zero,
         sum(noemp_n >= 9999)                   as noemp_9999
  from work.pop_num
  group by revline_group
  order by revline_group;
quit;

/* 10. NAICS sector code: share of missing codes (0) by approval year */
proc sql;
  select approval_year,
         count(*) as n_loans,
         sum(naics = '0')        as naics_missing,
         mean(naics = '0') * 100 as naics_missing_pct format=5.1
  from work.pop
  group by approval_year
  order by approval_year;
quit;

/* 11. Is missing NAICS related to the outcome? (possible leakage)
   Compare default rates of coded vs missing NAICS within each approval year.
   CALCULATED lets SAS reuse a column created earlier in the same SELECT. */
proc sql;
  select approval_year,
         sum(naics = '0')  as n_missing,
         sum(naics ne '0') as n_coded,
         sum(default_flag * (naics = '0'))  / calculated n_missing * 100
           as default_rate_missing format=6.2,
         sum(default_flag * (naics ne '0')) / calculated n_coded * 100
           as default_rate_coded format=6.2
  from work.pop
  where approval_year <= 2000
  group by approval_year
  order by approval_year;
quit;
