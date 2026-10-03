-- Winter Arc: Rangliste
-- Einmalig im Supabase SQL Editor ausführen (alles markieren, "Run").

-- 1) Tabelle: pro Person eine Zeile, zufällige ID statt Konto
create table if not exists public.scores (
  uid        uuid primary key,
  name       text not null check (char_length(name) between 1 and 20),
  streak     int  not null default 0 check (streak between 0 and 3650),
  done       int  not null default 0,
  total      int  not null default 0,
  day        date not null,
  updated_at timestamptz not null default now()
);

-- Direktzugriff sperren: RLS an, bewusst keine Policies.
-- Die Seite darf nur über die drei Funktionen unten lesen und schreiben.
alter table public.scores enable row level security;
revoke all on public.scores from anon, authenticated;

-- 2) Stand eintragen oder aktualisieren (Werte werden begrenzt)
create or replace function public.submit_score(
  p_uid uuid, p_name text, p_streak int, p_done int, p_total int
) returns void
language sql security definer set search_path = '' as $$
  insert into public.scores (uid, name, streak, done, total, day, updated_at)
  values (
    p_uid,
    left(trim(p_name), 20),
    greatest(0, least(p_streak, 3650)),
    greatest(0, least(p_done, p_total, 20)),
    greatest(0, least(p_total, 20)),
    (now() at time zone 'Europe/Berlin')::date,
    now()
  )
  on conflict (uid) do update set
    name = excluded.name, streak = excluded.streak, done = excluded.done,
    total = excluded.total, day = excluded.day, updated_at = now();
$$;

-- 3) Rangliste lesen (Top 20, ohne IDs; Streak zählt nur, wenn zuletzt gestern oder heute aktiv)
create or replace function public.get_leaderboard(p_uid uuid default null)
returns table (name text, streak int, done int, total int, is_today boolean, is_me boolean)
language sql security definer set search_path = '' as $$
  with t as (select (now() at time zone 'Europe/Berlin')::date as d)
  select s.name,
         case when s.day >= t.d - 1 then s.streak else 0 end,
         case when s.day = t.d then s.done else 0 end,
         s.total,
         s.day = t.d,
         s.uid = p_uid
  from public.scores s, t
  where s.updated_at > now() - interval '30 days'
  order by 2 desc, 3 desc, s.name
  limit 20;
$$;

-- 4) Sich selbst austragen (löscht die eigene Zeile)
create or replace function public.delete_score(p_uid uuid) returns void
language sql security definer set search_path = '' as $$
  delete from public.scores where uid = p_uid;
$$;

-- Nur diese Funktionen dürfen von der Seite aufgerufen werden
revoke all on function public.submit_score(uuid, text, int, int, int) from public;
revoke all on function public.get_leaderboard(uuid) from public;
revoke all on function public.delete_score(uuid) from public;
grant execute on function public.submit_score(uuid, text, int, int, int) to anon, authenticated;
grant execute on function public.get_leaderboard(uuid) to anon, authenticated;
grant execute on function public.delete_score(uuid) to anon, authenticated;
