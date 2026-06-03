-- Grain: one row per ranking_id

with rankings as (
    select *
    from {{ ref('stg_rankings') }}
),

firms as (
    select *
    from {{ ref('raw_firms') }}
),
practice_areas as (
    select *
    from {{ ref('raw_practice_areas') }}
)

select

    -- edition identifiers
    r.edition_id,
    r.edition_year,
    -- geography
    f.country as firm_country,
    f.city as firm_city,
    p.country as practice_area_country,

    -- entity identifiers
    r.ranking_id,
    r.firm_ref,
    f.firm_name,
    r.practice_area_id,
    p.practice_area,
    p.practice_group,
    p.sub_practice_area,

    -- ranking attributes
    r.ranking_tier,
    r.listing_type,
    r.commentary,

    -- status fields
    r.post_status,
    r.publication_status,

    case
        when lower(r.commentary) like '%firm recommended%'
             and r.ranking_tier = 0
        then 'not ranked'

        when lower(r.commentary) like '%firm to watch%'
             and r.ranking_tier = 0
             and r.post_status <> 'publish'
        then 'not ranked'

        else 'ranked'
    end as ranking_decision_status,

    -- timestamps
    r.modified_ts

from rankings r

left join firms f
    on r.firm_ref = f.firm_ref

left join practice_areas p
    on r.practice_area_id = p.practice_area_id
