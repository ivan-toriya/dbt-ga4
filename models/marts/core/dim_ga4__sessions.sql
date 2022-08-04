-- Dimension table for sessions based on the session_start event.
{% if is_incremental %}
    {% set partitions_to_replace = [] %}
    {% for i in range(var('static_incremental_days', 1)) %}
        {% set partitions_to_replace = partitions_to_replace.append('date_sub(current_date, interval ' + (i+1)|string + ' day)') %}
    {% endfor %}
    {{
        config(
            materialized = 'incremental',
            incremental_strategy = 'insert_overwrite',
            partition_by={
                "field": "session_start_date",
                "data_type": "date",
            },
            partitions = partitions_to_replace,
        )
    }}
{% else %}
    {{
        config(
            materialized = 'incremental',
            incremental_strategy = 'insert_overwrite',
            partition_by={
                "field": "session_start_date",
                "data_type": "date",
            },
        )
    }}
{% endif %}

with session_start_dims as (
    select 
        session_key,
        traffic_source,
        event_date_dt as session_start_date,
        ga_session_number,
        page_location as landing_page,
        page_hostname as landing_page_hostname,
        geo,
        device,
        row_number() over (partition by session_key order by session_event_number asc) as row_num
    from {{ref('stg_ga4__event_session_start')}}
    {% if is_incremental() %}
        {% if var('static_incremental_days', 1 ) %}
            where event_date_dt in ({{ partitions_to_replace | join(',') }})
        {% endif %}
    {% endif %}
),
-- Arbitrarily pull the first session_start event to remove duplicates
remove_dupes as 
(
    select * from session_start_dims
    where row_num = 1
),
join_traffic_source as (
    select 
        remove_dupes.*,
        session_source as source,
        session_medium as medium,
        session_campaign as campaign,
        session_default_channel_grouping as default_channel_grouping
    from remove_dupes
    left join {{ref('stg_ga4__sessions_traffic_sources')}} using (session_key)
)

select * from join_traffic_source