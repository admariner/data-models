/*
   Copyright 2020-2021 Snowplow Analytics Ltd. All rights reserved.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

-- Create upsert limit
DROP TABLE IF EXISTS {{.scratch_schema}}.pv_upsert_limit{{.entropy}};

CREATE TABLE {{.scratch_schema}}.pv_upsert_limit{{.entropy}} AS (
  SELECT
    DATEADD(DAY, -{{or .upsert_lookback_days 30}}, min(start_tstamp)) AS lower_limit
  FROM {{.scratch_schema}}.page_views_this_run{{.entropy}}
);

BEGIN;

  {{if ne (or .skip_derived false) true}}
    -- Commit production table
    DELETE FROM {{.output_schema}}.page_views{{.entropy}}
      WHERE page_view_id IN (SELECT page_view_id FROM {{.scratch_schema}}.page_views_this_run{{.entropy}})
        AND start_tstamp >= (SELECT lower_limit FROM {{.scratch_schema}}.pv_upsert_limit{{.entropy}});

    INSERT INTO {{.output_schema}}.page_views{{.entropy}}
      (SELECT * FROM {{.scratch_schema}}.page_views_this_run{{.entropy}});
  {{end}}

  {{if eq .stage_next true}}
    -- Commit staging table if enabled
    DELETE FROM {{.scratch_schema}}.page_views_staged{{.entropy}}
      WHERE page_view_id IN (SELECT page_view_id FROM {{.scratch_schema}}.page_views_this_run{{.entropy}});

    INSERT INTO {{.scratch_schema}}.page_views_staged{{.entropy}}
      (SELECT * FROM {{.scratch_schema}}.page_views_this_run{{.entropy}});
  {{end}}

  -- Commit metadata
  INSERT INTO {{.output_schema}}.datamodel_metadata{{.entropy}} (
    SELECT
      run_id,
      model_version,
      model,
      module,
      run_start_tstamp,
      GETDATE() AS run_end_tstamp,
      rows_this_run,
      distinct_key,
      distinct_key_count,
      time_key,
      min_time_key,
      max_time_key,
      duplicate_rows_removed,
      distinct_keys_removed
    FROM {{.scratch_schema}}.pv_metadata_this_run{{.entropy}}
  );

END;
