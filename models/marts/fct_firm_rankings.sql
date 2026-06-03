-- Grain: one row per ranking_id

select
    *

    , case
        when ranking_tier = 1 then true
        else false
      end as is_top_tier

    , case
        when ranking_tier in (1,2) then true
        else false
      end as is_top_two_tiers

    , case
        when publication_status = 'Active'
         and post_status = 'publish'
        then true
        else false
      end as is_published_active

    , case
        when ranking_decision_status = 'ranked'
        then true
        else false
      end as is_ranked

from {{ ref('int_rankings') }}