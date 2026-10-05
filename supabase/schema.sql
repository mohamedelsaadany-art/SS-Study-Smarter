-- SS Study Smarter: Telemetry Schema with Revisitor & Trend Analytics
-- Run in Supabase > SQL Editor

create table if not exists events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  vid text not null,
  kind text not null,
  exam_day int,
  n int not null default 1
);

alter table events enable row level security;
drop policy if exists "anon insert" on events;
create policy "anon insert" on events for insert to anon
  with check (kind in ('view','answered','part_done','exam_done') and n between 0 and 500 and length(vid) <= 64);
-- no select policy: visitors can write counts but never read them

create or replace function get_stats() returns json
language plpgsql security definer set search_path = public as $$
declare
  result json;
begin
  with visitor_first as (
    select vid, min((created_at at time zone 'Africa/Cairo')::date) as first_d
    from events
    group by vid
  ),
  daily_agg as (
    select
      (e.created_at at time zone 'Africa/Cairo')::date as d,
      count(distinct e.vid) as visitors,
      count(distinct case when f.first_d = (e.created_at at time zone 'Africa/Cairo')::date then e.vid end) as new_visitors,
      count(distinct case when f.first_d < (e.created_at at time zone 'Africa/Cairo')::date then e.vid end) as returning_visitors,
      count(*) filter (where e.kind = 'view') as views,
      coalesce(sum(e.n) filter (where e.kind = 'answered'), 0) as answered,
      count(*) filter (where e.kind = 'part_done') as parts_done,
      count(*) filter (where e.kind = 'exam_done') as exams_done
    from events e
    join visitor_first f on e.vid = f.vid
    where e.created_at > now() - interval '120 days'
    group by 1
  ),
  overall as (
    select
      count(distinct vid) as total_visitors,
      coalesce(sum(n) filter (where kind = 'answered'), 0) as total_answered,
      count(*) filter (where kind = 'exam_done') as total_exams,
      (select count(*) from (
        select vid from events group by vid having count(distinct (created_at at time zone 'Africa/Cairo')::date) > 1
      ) m) as total_revisitors
    from events
  )
  select json_build_object(
    'daily', (select coalesce(json_agg(r order by d), '[]'::json) from daily_agg r),
    'by_exam', (select coalesce(json_agg(r order by exam_day), '[]'::json) from (
      select exam_day, count(distinct vid) as visitors,
             coalesce(sum(n) filter (where kind = 'answered'), 0) as answered,
             count(*) filter (where kind = 'exam_done') as exams_done
      from events where exam_day is not null group by 1) r),
    'totals', (select json_build_object(
      'visitors', total_visitors,
      'revisitors', total_revisitors,
      'revisitor_rate', case when total_visitors > 0 then round((total_revisitors::numeric / total_visitors::numeric) * 100, 1) else 0 end,
      'answered', total_answered,
      'exams_done', total_exams
    ) from overall)
  ) into result;
  
  return result;
end $$;

grant execute on function get_stats() to anon;
grant insert on events to anon;

drop function if exists get_stats(text);
drop table if exists settings;
