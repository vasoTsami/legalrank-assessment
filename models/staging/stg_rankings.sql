with rankings as (
    select
        *,
        row_number() over (
            partition by ranking_id, edition_year
            order by
                try_cast(modified_ts as timestamp) desc,
                firm_ref desc,
                practice_area_id desc
        ) as rn
    from {{ ref('raw_rankings') }}
)

select
    r.ranking_id,
    try_cast(r.edition_year as integer) as edition_year,
    r.edition_id,
    r.firm_ref,
    r.practice_area_id,
coalesce(
    try_cast(ranking_tier as integer),
    try_cast(tier_rank as integer),
    case
        when tier_rank like 'TIER_%'
        then cast(replace(tier_rank, 'TIER_', '') as integer)
    end
) as ranking_tier,

    lower(trim(post_status)) as post_status,
    publication_status,
    listing_type,
    commentary,
    try_cast(modified_ts as timestamp) as modified_ts
from rankings r
inner join {{ ref('raw_firms') }} f
    on r.firm_ref = f.firm_ref
where rn = 1