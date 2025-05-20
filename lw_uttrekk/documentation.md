Dokumentasjon SharePoint: https://folkehelse.sharepoint.com/sites/1439/LabWare%20dokumentasjon/Datauttrekk.aspx

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

