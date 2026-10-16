/* Keep tables in a permanent library (WORK is deleted when the session ends) */
options compress=yes;
libname sba "~/sba_validation";

/* Load the raw CSV with every column as text, same as raw.sba_loans in PostgreSQL */
data sba.raw_loans;
  infile "~/sba_validation/SBAnational.csv" dsd firstobs=2 truncover lrecl=32767;
  length loannr_chkdgt $12 name $100 city $50 state $2 zip $6 bank $100
         bankstate $2 naics $6 approvaldate $12 approvalfy $5 term $5
         noemp $6 newexist $3 createjob $6 retainedjob $6 franchisecode $6
         urbanrural $3 revlinecr $3 lowdoc $3 chgoffdate $12
         disbursementdate $12 disbursementgross $20 balancegross $20
         mis_status $10 chgoffpringr $20 grappv $20 sba_appv $20;
  input (loannr_chkdgt -- sba_appv) (:$100.);
  /* Remove a Windows line-end character if the file has one */
  sba_appv = compress(sba_appv, '0D'x);
run;