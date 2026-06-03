# LegalRank — Senior Data Engineer Technical Assessment

## Overview

This project implements a dbt pipeline for LegalRank rankings and submissions data.

The solution addresses:

* Schema evolution in the rankings feed
* Deduplication of incremental loads
* Data quality validation
* Freshness monitoring
* Volume monitoring
* Schema drift detection
* Client-facing mart construction


### Layers

#### Staging

The staging layer standardises source data, applies type casting, handles schema migration logic and removes duplicate records.

Key decisions:

* `ranking_tier` and `tier_rank` are unified into a single integer column.
* `post_status` values are normalised to lower case.
* Latest-record-wins deduplication is implemented using `row_number()` ordered by `modified_ts`.
* Invalid firm references are excluded.

#### Intermediate

The intermediate layer enriches rankings with firm and practice area metadata and applies business classification logic.

`ranking_decision_status` is derived according to the supplied business rules.

Grain: one row per `ranking_id`.

#### Mart

The mart is designed for the Top Tier Firms product.

Additional flags were created to support common product filters:

* `is_top_tier`
* `is_top_two_tiers`
* `is_published_active`
* `is_ranked`

These reduce complexity for downstream reporting and client applications.


## Data Quality

### Error-level Tests

Where downstream reporting would be incorrect or impossible:

* Primary key uniqueness
* Required business keys
* Referential integrity
* Mandatory timestamps

### Warning-level Tests

Where data remains usable but requires investigation:

* Email format validation
* Unexpected workflow states
* Volume anomalies

This approach prevents unnecessary pipeline failures while protecting critical business outputs.

## Test Design Rationale

The goal of the tests provided is to distinguish between data issues that prevent delivery of the client product and data issues that should be investigated but do not justify stopping the pipeline.

Examples:

- Duplicate ranking_id values are treated as errors because they can create inconsistent rankings and duplicate records in downstream products.
- Missing firm references are treated as errors because rankings cannot be attributed to a firm and therefore cannot be displayed correctly.
- Unexpected post_status values are treated as warnings because new workflow states may be introduced by the CMS without necessarily impacting consumers.
- Email format validation is treated as a warning because it does not affect ranking calculations.
- Volume anomaly tests are treated as warnings initially, with escalation to P1 only when the downstream product is at risk.


## Monitoring

### Freshness

Freshness thresholds are aligned to operational SLAs.

Fivetran syncs:

* 20:00 UTC
* 02:00 UTC

Client-facing marts must be available by 07:00 UTC.

Thresholds:
The latest expected source refresh occurs at 02:00 UTC and client-facing marts must be available by 07:00 UTC.

- Warning: 5 hours (source is approaching the SLA boundary)
- Error: 6 hours (risk of missing the 07:00 delivery target)

This provides approximately one hour for investigation and remediation before the SLA is breached.

### Volume Monitoring

Volume monitoring protects the Top Tier Firms widget.

Controls implemented:

* Row-count floor test
* Elementary volume anomaly configuration

### Schema Drift

Schema drift detection was configured using Elementary schema monitoring.

The test is designed to detect:

* Added columns
* Removed columns
* Renamed columns
* Type changes


## Assumptions

* `ranking_id` is the business grain for rankings.
* The latest `modified_ts` record represents the correct version.
* Rankings with invalid firm references should not be surfaced to client products.
* Unexpected `post_status` values should generate warnings rather than fail the pipeline.
* raw_firms and raw_practice_areas are treated as source data
* no separate staged dimensions were requested
* ranking_tier domain assumed to be 0–5 based on supplied data
* volume thresholds derived from observed dataset size

## Running the Project

```bash
dbt deps
dbt seed
dbt build
dbt docs generate
```


## Notes

Elementary monitoring configuration is included in the project. Elementary tests were left commented in the submitted version due to compatibility issues between the package version and the local DuckDB/dbt environment used for the assessment.
