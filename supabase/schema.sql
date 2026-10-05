-- Run once in Supabase > SQL Editor. Change 'CHANGE-ME' to your dashboard passphrase first.
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

create table if not exists settings (k text primary key, v text not null);
alter table settings enable row level security;
insert into settings values ('dash_key', 'CHANGE-ME') on conflict (k) do update set v = excluded.v;

create or replace function get_stats(p_key text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if p_key is distinct from (select v from settings where k = 'dash_key') then
    raise exception 'forbidden';
  end if;
  return json_build_object(
    'daily', (select coalesce(json_agg(r order by d), '[]'::json) from (
      select (created_at at time zone 'Africa/Cairo')::date as d,
             count(distinct vid) as visitors,
             count(*) filter (where kind = 'view') as views,
             coalesce(sum(n) filter (where kind = 'answered'), 0) as answered,
             count(*) filter (where kind = 'part_done') as parts_done,
             count(*) filter (where kind = 'exam_done') as exams_done
      from events where created_at > now() - interval '120 days' group by 1) r),
    'by_exam', (select coalesce(json_agg(r order by exam_day), '[]'::json) from (
      select exam_day, count(distinct vid) as visitors,
             coalesce(sum(n) filter (where kind = 'answered'), 0) as answered,
             count(*) filter (where kind = 'exam_done') as exams_done
      from events where exam_day is not null group by 1) r),
    'totals', (select json_build_object('visitors', count(distinct vid),
             'answered', coalesce(sum(n) filter (where kind = 'answered'), 0),
             'exams_done', count(*) filter (where kind = 'exam_done')) from events)
  );
end $$;
grant execute on function get_stats(text) to anon;

grant insert on events to anon;
