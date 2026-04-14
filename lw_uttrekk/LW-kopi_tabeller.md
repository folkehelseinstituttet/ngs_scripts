Installere R-pakker:
```
install.packages("odbc", repos = "file:///G:/R-server/cran/cran.uib.no")
```

Dokumentasjon SharePoint: https://folkehelse.sharepoint.com/sites/1439/LabWare%20dokumentasjon/Datauttrekk.aspx

# SAMPLES

For å hente ut informasjon om **prøvene** (metadata), se i `SAMPLE_VIEW`. 

`tbl(con, "SAMPLE_VIEW")`.  

Den har følgende kolonner:  
`colnames(tbl(con, "SAMPLE_VIEW"))`

| Kolonne           | Beskrivelse       |
|--------------------------|-----------------------|
| SAMPLE_NUMBER            | Labware-nummer        |
| TEXT_ID                  |                       |
| X_CUSTOMER_SAMPLE_ID     |                       |
| STATUS                   | Status på prøven. Kan inneholde følgende symboler: A = Authorized. X = Cancelled. R = Rejected. C = Complete. P = In-progress. I = Incomplete. U = Unreceived                       |
| OLD_STATUS               |                       |
| ORIGINAL_SAMPLE          |                       |
| PARENT_SAMPLE            |                       |
| SAMPLE_VOLUME            |                       |
| SAMPLE_UNITS             |                       |
| LOGIN_DATE               |                       |
| LOGIN_BY                 |                       |
| SAMPLED_DATE             | Prøve-tatt dato                      |
| RECD_DATE                | Prøve-mottatt dato                      |
| RECEIVED_BY              |                       |
| DATE_STARTED             |                       |
| STARTED                  |                       |
| DUE_DATE                 |                       |
| DATE_COMPLETED           |                       |
| DATE_REVIEWED            |                       |
| REVIEWER                 |                       |
| REVIEW_NOTE              |                       |
| PROJECT                  |                       |
| BATCH_NAME               |                       |
| BATCH_TEMPLATE           |                       |
| SAMPLE_TYPE              |                       |
| SAMPLE_NAME              |                       |
| DESCRIPTION              |                       |
| PRIORITY                 |                       |
| TEST_LIST                |                       |
| TEMPLATE                 |                       |
| STANDARD                 |                       |
| CONDITION                |                       |
| TARGET_DATE              |                       |
| CHANGED_ON               |                       |
| BATCH                    |                       |
| ORDER_NUM                |                       |
| STORAGE_CONDITION        |                       |
| HAS_FLAGS                |                       |
| LABEL_ID                 |                       |
| X_GENDER                 |                       |
| X_ZIPCODE                |                       |
| X_SPECIMEN_SOURCE        |                       |
| X_SAMPLE_CATEGORY        |                       |
| X_SAMPLE_SUBCAT          |                       |
| X_REPORT_COMMENTS        |                       |
| FOR_ENTITY               |                       |
| X_PATIENT_AGE            |                       |
| GROUP_NAME               |   Faggruppe                    |
| STORAGE_LOC_NO           |                       |
| X_MEDICAL_REVIEW_BY      |                       |
| X_MEDICAL_REVIEW_ON      |                       |
| X_START_APPROVED         |                       |
| X_START_APPROVED_BY      |                       |
| X_START_APPROVED_ON      |                       |
| X_READY_FOR_MED_REV      |                       |
| X_SAMPLE_COMMENT         |                       |
| X_OBJECT_TYPE            |                       |
| X_INFLU_ID               |                       |
| X_TREND_DATE             |                       |
| X_TREND_DATE_TYPE        |                       |
| X_ACCESSION_CODE         |                       |
| ON_WORKBOOK              |                       |
| X_AGENS                  | Agens. Merk at denne ikke alltid brukes ved registrering av prøven.                      |
| X_MEDICAL_REVIEW         | Status på prøven. Kan inneholde følgende symboler: A = Authorized. X = Canceled. N = Not reviewed. R = Rejected. NA = Missing information                      |
| X_SAMPLE_LOC_ID          |                       |
| BIRTH_DATE               |   Fødselsdato                    |
| GENDER                   |   Kjønn                    |
|PATIENT| Info om prøve er fra samme pasient |


# TESTS  

For å hente ut informasjon om **testene** (metadata), se i `TEST_VIEW`. 

`tbl(con, "TEST_VIEW")`.  

Den har følgende kolonner:  
`colnames(tbl(con, "TEST_VIEW"))`

| Kolonne           | Beskrivelse       |
|--------------------------|-----------------------|
|TEST_NUMBER| |
|ANALYSIS||
|VERSION||
|SAMPLE_NUMBER||
|REPLICATE_COUNT||
|STATUS||
|OLD_STATUS||
|REPLICATE_TEST||
|TEST_COMMENT||
|GROUP_NAME||
|EXPECTED_DATE||
|CHANGED_ON||
|BATCH||
|REPORTED_NAME||
|VARIATION||
|TEST_LIST||
|ON_WORKSHEET||
|PHONE_DOC||
|PARENT_TEST||
|ORIGINAL_TEST||
|QC_REFERENCE||
|X_REPORT_COMMENTS||
|BATCH_LINK||
|HAS_FLAGS||
|X_INVOICE||
|X_APPROVE||
|X_STORAGE_LOC_NO||
|X_TECH_REVIEW||
|X_TECH_REVIEW_BY||
|X_TECH_REVIEW_ON||
|X_COA_DESC||
|X_EMSIS_SUBTYPE||
|X_EMSIS_RESISTENS||
|ON_WORKBOOK||
|X_AGENS||
|ALIAS||

# Ordre-tabellen

`tbl(con, "ORDERS_VIEW")`.

| Kolonne           | Beskrivelse       |
|--------------------------|-----------------------|
|ORDER_NUM| Kobling til "SAMPLE_VIEW" for eksempel |
|LAST_ORDER_NUM||
|CHANGED_BY||
|CHANGED_ON||
|CLOSED||
|DESCRIPTION||
|GROUP_NAME||
|TEMPLATE||
|REQUIRED_DATE||
|STATUS||
|OLD_STATUS||
|CREATED_BY||
|CREATED_ON||
|ACCEPTED_BY||
|ACCEPTED_ON||
|SAMPLED_BY||
|SAMPLED_ON||
|RECEIVED_BY||
|RECEIVED_ON||
|CANCELED_BY||
|CANCELED_ON||
|CANCELED_REASON||
|CLOSED_BY||
|CLOSED_ON||
|REVIEWED_BY||
|REVIEWED_ON||
|SCHED_START_DATE||
|SCHED_END_DATE||
|SCHEDULED_TIME||
|OBSERVATIONS||
|IMPORTANT_MESSAGE||
|TEST_LIST||
|HAS_FLAGS||
|MERGED_ORDER_NUM||
|MERGED||
|X_PATIENT_AGE||
|X_CLINICIAN||
|X_GENDER||
|X_PATIENT_TYPE||
|X_COPY_TO||
|X_ORDER_EXKOM||
|X_CUSTOMER_REF_NR||
|X_DIAGNOSE||
|X_PATIENT_COM||
|X_APPROVED||
|X_APPROVED_ON||
|X_APPROVED_BY||
|X_COA_STATUS||
|X_ORDER_COMMENTS||
|X_COA_DIRECTOR||
|X_COA_DIR_TXT||
|X_COA_MEDVAL_TXT||
|X_SAMPLE_CATEGORY||
|x_sample_submitter||
|X_INFLU_ID||
|SAMPLE_TYPE||
|X_CUSTOMER_CATEGORY||
|X_SAMPLED_LOC_ZIP||
|FOR_ENTITY| Info om prøve er fra samme pasient |
|FOR_ENTITY_DESC||
|x_contam_country||
|X_GB_REKVID||
|X_COMMUNE||
|ABOUT_ENTITY||

# Resultater-tabellen

`tbl(con, "RESULTS_VIEW")`.

| Kolonne           | Beskrivelse       |
|--------------------------|-----------------------|
|value||
|RESULT_NUMBER||
|TEST_NUMBER||
|NAME||
|REPLICATE_COUNT||
|ORDER_NUMBER||
|RESULT_TYPE||
|UNITS||
|MINIMUM||
|MAXIMUM||
|ALLOW_OUT||
|FORMATTED_ENTRY||
|ENTRY||
|ROUND||
|PLACES||
|DATE_REVIEWED||
|STATUS||
|OLD_STATUS||
|ENTERED_ON||
|ENTERED_BY||
|REVIEWER||
|ANALYSIS||
|SAMPLE_NUMBER||
|INSTRUMENT||
|USES_INSTRUMENT||
|USES_CODES||
|IN_CAL||
|AUTO_CALC||
|LIST_KEY||
|ALLOW_CANCEL||
|REPORTABLE||
|OPTIONAL||
|CODE_ENTERED||
|CHANGED_ON||
|STD_REAG_SAMPLE||
|HAS_ATTRIBUTES||
|FACTOR_VALUE||
|FACTOR_OPERATOR||
|NUMERIC_ENTRY||
|ENTRY_TYPE||
|MIN_LIMIT||
|MAX_LIMIT||
|ALIAS_NAME||
|CONTROL_1||
|CONTROL_2||
|IN_CONTROL||
|DISPLAYED||
|REPORTED_NAME||
|ENTRY_QUALIFIER||
|SPEC_OVERRIDE||
|BATCH||
|X_REPORT_NAME||
|X_REPORT_CDC||
|X_N_TEST||
|X_EMSIS_STATUS||
|X_N_RESULT||
|X_EMSIS_DATE||
|X_RESET_VAL||
|X_COA_DESC||
|X_N_V_OR_S||
|X_EMSIS_TYPE||
|DOUBLE_ENTRY_CHK||
|MODIFIED_RESULT||
|FIRST_ENTRY||
|FIRST_ENTRY_BY||
|FIRST_ENTRY_ON||
|DB_FILE||
|USES_TABULAR_RSLTS||
|TAB_RESULTS_REV_NO||
|X_TABRES_RETURNMODE||
|X_TABRES_RETURNNAME||
|X_TABRES_SEARCHTERM||
|X_TABRES_SOURCE||
|X_TABRES_NAME||

