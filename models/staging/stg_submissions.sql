with submissions as (

    select
        *,
        row_number() over (
            partition by submission_id
            order by created_ts desc
        ) as rn

    from {{ source('main', 'raw_submissions') }}

)

select
    cast(submission_id as varchar) as submission_id,
    cast(firm_ref as varchar) as firm_ref,
    cast(practice_area_id as varchar) as practice_area_id,
    cast(edition_year as integer) as edition_year,

    case
        when lower(trim(submission_type))
             in ('firm','law_firm','law firm')
        then 'firm'
        else lower(trim(submission_type))
    end as submission_type,

    lower(trim(submitted_by_email)) as submitted_by_email,

    try_cast(submitted_at as timestamp) as submitted_at,

    try_cast(num_referees as integer) as num_referees,

    lower(trim(status)) as status,

    try_cast(created_ts as timestamp) as created_ts

from submissions s
where rn = 1
and exists (
    select 1
    from {{ source('main', 'raw_firms') }} f
    where f.firm_ref = s.firm_ref
)