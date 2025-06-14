DOC_AI_DB.DOC_AI_SCHEMA.MY_PDF_STAGEDOC_AI_DB.DOC_AI_SCHEMA.MY_PDF_STAGE-- use doc_ai database and schema
USE DATABASE doc_ai_db;
USE SCHEMA doc_ai_db.doc_ai_schema;

-- create internal stage, stream and refresh metadata
CREATE OR REPLACE STAGE my_pdf_stage
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

CREATE STREAM my_pdf_stream ON STAGE my_pdf_stage;

ALTER STAGE my_pdf_stage REFRESH; 

  -- create table
CREATE OR REPLACE TABLE pdf_reviews (
  file_name VARCHAR,
  file_size VARIANT,
  last_modified VARCHAR,
  snowflake_file_url VARCHAR,
  json_content VARCHAR
);

-- check the stage, table and  stream
SELECT * FROM DIRECTORY(@my_pdf_stage);
SELECT * FROM my_pdf_stream;


--create task
CREATE OR REPLACE TASK load_new_file_data
  WAREHOUSE = compute_wh
  SCHEDULE = '1 minute'
  COMMENT = 'Process new files in the stage and insert data into the pdf_reviews table.'
WHEN SYSTEM$STREAM_HAS_DATA('my_pdf_stream')
AS
INSERT INTO pdf_reviews (
  SELECT
    RELATIVE_PATH AS file_name,
    size AS file_size,
    last_modified,
    file_url AS snowflake_file_url,
    inspection_reviews!PREDICT(GET_PRESIGNED_URL('@my_pdf_stage', RELATIVE_PATH), 1) AS json_content
  FROM my_pdf_stream
  WHERE METADATA$ACTION = 'INSERT'
);

ALTER TASK load_new_file_data RESUME;
SELECT * FROM pdf_reviews;

CREATE OR REPLACE TABLE doc_ai_db.doc_ai_schema.pdf_reviews_2 AS (
 WITH temp AS (
   SELECT
     RELATIVE_PATH AS file_name,
     size AS file_size,
     last_modified,
     file_url AS snowflake_file_url,
     inspection_reviews!PREDICT(get_presigned_url('@my_pdf_stage', RELATIVE_PATH), 1) AS json_content
   FROM directory(@my_pdf_stage)
 )

 SELECT
   file_name,
   file_size,
   last_modified,
   snowflake_file_url,
   json_content:__documentMetadata.ocrScore::FLOAT AS ocrScore,
   f.value:score::FLOAT AS inspection_date_score,
   f.value:value::STRING AS inspection_date_value,
   g.value:score::FLOAT AS inspection_grade_score,
   g.value:value::STRING AS inspection_grade_value,
   i.value:score::FLOAT AS inspector_score,
   i.value:value::STRING AS inspector_value,
   ARRAY_TO_STRING(ARRAY_AGG(j.value:value::STRING), ', ') AS list_of_units
 FROM temp,
   LATERAL FLATTEN(INPUT => json_content:inspection_date) f,
   LATERAL FLATTEN(INPUT => json_content:inspection_grade) g,
   LATERAL FLATTEN(INPUT => json_content:inspector) i,
   LATERAL FLATTEN(INPUT => json_content:list_of_units) j
 GROUP BY ALL
);

SELECT * FROM pdf_reviews_2;