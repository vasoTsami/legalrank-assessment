
### 5C – Schema Drift Detection

I implemented schema drift monitoring on `stg_rankings` using Elementary's `schema_changes` test.

The test detects:

* New columns added by the source system
* Existing columns removed
* Column renames
* Data type changes

I chose Elementary because it integrates directly with dbt metadata and provides automated schema change detection without requiring custom SQL tests.

The test is configured with `severity: error` because schema changes in the rankings feed can invalidate downstream transformations and reporting logic. Failing the pipeline immediately makes upstream changes visible before they impact the Top Tier Firms product.

### 5D

### 1. Downstream dependency alerting

When schema drift is detected on `stg_rankings`, I would use the dbt lineage graph and metadata catalog to identify all downstream dependencies. Starting from `stg_rankings`, dbt can determine which intermediate models, marts, exposures, dashboards, and client products depend on the affected columns. The alert should include the impacted lineage path (for example: `stg_rankings → int_rankings → fct_firm_rankings → Top Tier Firms widget`) so responders immediately understand business impact and can prioritise remediation.

### 2. Alerting tiers

**P1 (page on-call, 24/7)**

Conditions:

* `fct_firm_rankings` not refreshed by 07:00 UTC
* Source freshness exceeds SLA
* Schema drift causes model failures
* Volume anomaly causing significant row-count reduction (e.g. >30%)
* Empty mart or failed production dbt run

Examples:

* `raw_rankings` not loaded overnight
* `fct_firm_rankings` contains zero rows
* `ranking_tier` column removed from source

Routing: PagerDuty (or equivalent). These conditions directly affect the client-facing Top Tier Firms product and require immediate action.

**P2 (Slack/Teams, business hours)**

Conditions:

* Minor volume anomalies
* Warning-level freshness breaches
* New nullable columns added
* Non-critical test failures
* Documentation or metadata issues

Examples:

* 10% drop in daily rankings volume
* New source column introduced but not yet consumed

Routing: Slack/Microsoft Teams because investigation can occur during business hours without customer impact.

### 3. Stale data runbook

1. Confirm freshness by querying `fct_firm_rankings` and checking the latest `modified_ts`.
2. Run `dbt source freshness` to identify whether `raw_rankings` or `raw_submissions` are stale.
3. Inspect recent dbt logs (`logs/dbt.log`) for model or test failures.
4. Execute `dbt build --select stg_rankings+` to determine the first failing model in the lineage.
5. If sources are stale, escalate to the ingestion/Fivetran owner. If transformations are failing, fix the issue, rerun the pipeline, validate row counts, and confirm the mart is refreshed.

### 4. Pre-ingestion quality gates

The current solution detects problems after data has already landed in the warehouse and dbt has started processing it. A better design is to add a validation layer between Fivetran and the warehouse tables used by dbt. For example, Fivetran could load data into a raw landing area. Before promoting data to the curated raw tables consumed by dbt, an automated validation process would run schema and volume checks.

The validation would compare the incoming dataset against an expected contract:

* Required columns exist (`ranking_id`, `firm_ref`, etc.)
* Expected data types match
* No unexpected column removals or renames
* Row counts remain within expected ranges
* Critical business keys are not null

In this incident, the CMS deployment introduced new columns (`tier_rank`, `listing_type`) and changed field behaviour (`ranking_tier` became null for new records). A pre-ingestion schema contract would have detected the change before the data reached `stg_rankings` and could have automatically quarantined the affected batch.

In the same way, a volume check would have detected the sudden increase of 847 records and flagged it for review before downstream models ran.

This approach prevents bad data from entering the transformation layer, reduces production failures, and provides faster feedback to upstream system owners when contracts are broken.



### Task 6 – Incident Diagnosis

#### 1. Root cause analysis

The CMS deployment introduced a schema change to the rankings export. The Fivetran log shows 847 additional records were loaded during the incremental sync:

`12,847 rows synced (+847 vs previous sync)`

The 847 failures in `unique_stg__rankings_ranking_id` match the number of newly synced rows exactly. This suggests that post-migration records were loaded alongside existing versions of the same rankings and the staging deduplication logic did not successfully retain only the latest record per `ranking_id`.

The `not_null_stg__rankings_firm_ref` failure indicates that 12 ranking records arrived without a valid firm reference. These records cannot be linked to a firm and should be quarantined and investigated with the CMS team.

The `accepted_values_stg__rankings_post_status` warning indicates 34 records contain status values outside the expected set (`publish`, `draft`, `pending`, `trash`). This suggests the CMS deployment introduced new workflow states or the status standardisation logic was not applied before testing.

In a nutshell, the 847 duplicate ranking IDs point to the 847 newly synced records reported by Fivetran. This indicates the CMS schema migration introduced a second version of existing rankings and the staging deduplication logic did not correctly retain only the latest record per ranking_id.

The 12 null firm_ref failures indicate records that cannot be linked to a firm. These records should be quarantined and investigated with the CMS team.

The 34 post_status warnings suggest new status values were introduced during the CMS deployment or the standardisation logic was not applied before testing. Because the test is configured as a warning, processing can continue while the new values are reviewed.

#### 2. Restoring the 07:00 UTC SLA

1. Identify the 847 duplicate `ranking_id` records and confirm they represent multiple versions of the same ranking.
2. Rebuild `stg__rankings` using latest-record deduplication (`row_number()` ordered by `modified_ts desc`).
3. Exclude or quarantine the 12 records with null `firm_ref`.
4. Review the 34 unexpected `post_status` values and either map them to valid statuses or temporarily allow them.
5. Run `dbt build --select stg_rankings+ fct_firm_rankings`, validate row counts and freshness, then release the refreshed mart.

#### 3. Self-healing architectural improvement

Implement a Bronze/Silver ingestion pattern. Fivetran data lands unchanged in a raw history layer, while a promotion layer automatically deduplicates records by `ranking_id`, keeps the latest `modified_ts`, validates required business keys, and detects schema or volume anomalies before data reaches dbt staging. Invalid records are quarantined automatically while valid records continue downstream, reducing manual intervention and preventing similar incidents from impacting client-facing products.



