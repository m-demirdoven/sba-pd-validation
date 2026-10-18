/* =====================================================
   03_univariate.sas
   Default rate by category, development sample only.
   Modelling decisions use the development sample only,
   so the out-of-time test stays clean.
   ===================================================== */

libname sba "~/sba_validation";

/* Mean of a 0/1 flag = default rate.
   WAYS 1 gives one table per variable instead of all combinations. */
proc means data=sba.clean_loans n mean maxdec=4;
  where sample = 'development';
  class business_type revolving lowdoc;
  ways 1;
  var default_flag;
run;

/* Is the revolving gap real, or driven by approval year mix?
   Compare default rates of N / Unknown / Y within each approval year. */
proc sql;
  select approval_year,
         sum(revolving = 'N')       as n_n,
         sum(revolving = 'Unknown') as n_unknown,
         sum(revolving = 'Y')       as n_y,
         case when calculated n_n > 0
              then sum(default_flag * (revolving = 'N')) / calculated n_n * 100
         end as dr_n format=6.2,
         case when calculated n_unknown > 0
              then sum(default_flag * (revolving = 'Unknown')) / calculated n_unknown * 100
         end as dr_unknown format=6.2,
         case when calculated n_y > 0
              then sum(default_flag * (revolving = 'Y')) / calculated n_y * 100
         end as dr_y format=6.2
  from sba.clean_loans
  where sample = 'development'
  group by approval_year
  order by approval_year;
quit;




/* Same within-year check for business_type and lowdoc.
   PROC TABULATE builds a year x category table:
   N = number of loans, Mean = default rate. */
proc tabulate data=sba.clean_loans;
  where sample = 'development';
  class approval_year business_type lowdoc;
  var default_flag;
  table approval_year, business_type*(n*f=comma8. default_flag*mean*f=6.4);
  table approval_year, lowdoc*(n*f=comma8. default_flag*mean*f=6.4);
run;



/* Sector (2-digit NAICS): default rate in the development sample,
   sorted from riskiest to safest */
proc sql;
  select sector,
         count(*)                 as n_loans,
         mean(default_flag) * 100 as default_rate_pct format=6.2
  from sba.clean_loans
  where sample = 'development'
  group by sector
  order by default_rate_pct desc;
quit;


/* Year-adjusted sector risk index = observed defaults / expected defaults.
   Expected = default rate of all development loans approved in the same year.
   Index above 1 means riskier than the average loan of the same year. */

/* Step 1: default rate of each approval year */
proc means data=sba.clean_loans noprint nway;
  where sample = 'development';
  class approval_year;
  var default_flag;
  output out=work.year_dr(drop=_type_ _freq_) mean=year_dr;
run;

/* Step 2: development loans sorted by year (MERGE needs both tables sorted) */
proc sort data=sba.clean_loans(keep=sample approval_year sector default_flag
                               where=(sample = 'development'))
          out=work.dev;
  by approval_year;
run;

/* Step 3: attach the year default rate to every loan */
data work.dev;
  merge work.dev work.year_dr;
  by approval_year;
run;

/* Step 4: number of loans, observed and expected defaults per sector */
proc means data=work.dev noprint nway;
  class sector;
  var default_flag year_dr;
  output out=work.sector_idx(drop=_type_ rename=(_freq_=n_loans))
         sum=observed expected;
run;

/* Step 5: default rate and risk index, riskiest sector first */
data work.sector_idx;
  set work.sector_idx;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc sort data=work.sector_idx;
  by descending risk_index;
run;

proc print data=work.sector_idx noobs;
  var sector n_loans default_rate risk_index;
run;




/* Sector groups based on the year-adjusted risk index (development sample).
   Unknown (index 1.06) joins the above-average group, so no category
   disappears after 2001 when NAICS codes became complete.
   OTHER catches any code not listed, so unexpected values are visible. */
proc format;
  value $sector_grp
    '45'                                    = 'S1 high'
    '11','48','31','44','71','53','72','32',
    '49','51','Unknown'                     = 'S2 above average'
    '23','81','56','42','33','61'           = 'S3 below average'
    '21','54','92','62','22','52','55'      = 'S4 low'
    other                                   = 'Unmapped';
run;

/* Check the groups. CLASS groups by the formatted value,
   so loans are summed by sector group, not by sector code. */
proc means data=work.dev noprint nway;
  class sector / order=formatted;
  format sector $sector_grp.;
  var default_flag year_dr;
  output out=work.sector_grp_idx(drop=_type_ rename=(_freq_=n_loans))
         sum=observed expected;
run;

data work.sector_grp_idx;
  set work.sector_grp_idx;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc print data=work.sector_grp_idx noobs;
  var sector n_loans default_rate risk_index;
run;



/* Rebuild the development table with all variables
   and the year default rate attached to every loan */
proc sort data=sba.clean_loans(where=(sample = 'development')) out=work.dev;
  by approval_year;
run;

data work.dev;
  merge work.dev work.year_dr;
  by approval_year;
run;

/* State: year-adjusted risk index, riskiest first */
proc means data=work.dev noprint nway;
  class state;
  var default_flag year_dr;
  output out=work.state_idx(drop=_type_ rename=(_freq_=n_loans))
         sum=observed expected;
run;

data work.state_idx;
  set work.state_idx;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc sort data=work.state_idx;
  by descending risk_index;
run;

proc print data=work.state_idx noobs;
  var state n_loans default_rate risk_index;
run;


/* State groups based on the year-adjusted risk index (development sample).
   Cut points at index 1.25, 1.00 and 0.80. */
proc format;
  value $state_grp
    'KY','AR','LA','WV','SC','TX','OK','MS','TN','IL','AL'      = 'T1 high'
    'MI','NY','MO','FL','GA','OH','IN','KS','NC','CO','NM',
    'NV','DE'                                                   = 'T2 above average'
    'NJ','PA','CT','ID','ND','NE','WI','ME','IA','OR','VA',
    'MD','AZ','VT','WA'                                         = 'T3 below average'
    'HI','UT','DC','MN','AK','MA','CA','SD','RI','WY','NH','MT' = 'T4 low'
    other                                                       = 'Unmapped';
run;

/* Check the groups */
proc means data=work.dev noprint nway;
  class state / order=formatted;
  format state $state_grp.;
  var default_flag year_dr;
  output out=work.state_grp_idx(drop=_type_ rename=(_freq_=n_loans))
         sum=observed expected;
run;

data work.state_grp_idx;
  set work.state_grp_idx;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc print data=work.state_grp_idx noobs;
  var state n_loans default_rate risk_index;
run;


/* State groups based on the year-adjusted risk index (development sample).
   Cut points at index 1.25, 1.00 and 0.80.
   9 development loans have no state. They go to T3, the group closest
   to the average loan (index 1.0). */
proc format;
  value $state_grp
    'KY','AR','LA','WV','SC','TX','OK','MS','TN','IL','AL'      = 'T1 high'
    'MI','NY','MO','FL','GA','OH','IN','KS','NC','CO','NM',
    'NV','DE'                                                   = 'T2 above average'
    'NJ','PA','CT','ID','ND','NE','WI','ME','IA','OR','VA',
    'MD','AZ','VT','WA',' '                                     = 'T3 below average'
    'HI','UT','DC','MN','AK','MA','CA','SD','RI','WY','NH','MT' = 'T4 low'
    other                                                       = 'Unmapped';
run;

/* Check the groups. MISSING keeps blank states in the table;
   without it CLASS drops them without any warning. */
proc means data=work.dev noprint nway;
  class state / missing order=formatted;
  format state $state_grp.;
  var default_flag year_dr;
  output out=work.state_grp_idx(drop=_type_ rename=(_freq_=n_loans))
         sum=observed expected;
run;

data work.state_grp_idx;
  set work.state_grp_idx;
  default_rate = observed / n_loans;
  risk_index   = observed / expected;
  format default_rate percent8.2 risk_index 6.2;
run;

proc print data=work.state_grp_idx noobs;
  var state n_loans default_rate risk_index;
run;