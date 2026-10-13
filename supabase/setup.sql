-- Friendsgiving RSVP: database setup
-- Paste this whole file into Supabase → SQL Editor → New query → Run. Safe to re-run.
--
-- Design
--   rsvps          public guest list + potluck board (readable by anyone with the link)
--   rsvp_private   phone numbers and dietary notes (hosts only, via the dashboard)
--   submit_rsvp()  the only way to write: validates input, enforces the headcount cap,
--                  and writes both tables in one transaction

-- ---------- tables ----------
create table if not exists public.rsvps (
  id             uuid primary key default gen_random_uuid(),
  name           text not null check (char_length(name) between 1 and 60),
  status         text not null check (status in ('yes', 'maybe', 'no', 'waitlist')),
  plus_one       boolean not null default false,
  plus_one_name  text check (char_length(plus_one_name) <= 60),
  dish_category  text check (dish_category in ('main', 'side', 'dessert', 'drinks', 'other')),
  dish           text check (char_length(dish) <= 80),
  created_at     timestamptz not null default now()
);

create table if not exists public.rsvp_private (
  rsvp_id  uuid primary key references public.rsvps (id) on delete cascade,
  phone    text check (char_length(phone) <= 30),
  dietary  text check (char_length(dietary) <= 200)
);

-- ---------- row level security ----------
alter table public.rsvps        enable row level security;
alter table public.rsvp_private enable row level security;

drop policy if exists "Guest list is public" on public.rsvps;
create policy "Guest list is public"
  on public.rsvps for select
  to anon, authenticated
  using (true);
-- No insert/update/delete policies: direct writes are blocked. Writes go through submit_rsvp().
-- rsvp_private has no policies at all: the browser can never read it.

revoke all on public.rsvps        from anon, authenticated;
revoke all on public.rsvp_private from anon, authenticated;
grant select on public.rsvps to anon, authenticated;

-- ---------- write path ----------
create or replace function public.submit_rsvp(
  p_name           text,
  p_status         text,
  p_plus_one       boolean,
  p_plus_one_name  text,
  p_dish_category  text,
  p_dish           text,
  p_phone          text,
  p_dietary        text
)
returns table (rsvp_id uuid, final_status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_capacity constant int := 35;   -- headcount cap, plus-ones included
  v_status   text := p_status;
  v_taken    int;
  v_id       uuid;
begin
  if p_status not in ('yes', 'maybe', 'no') then
    raise exception 'Pick yes, maybe, or no.';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Add your name.';
  end if;

  -- Serialize RSVPs so two people can't grab the last spot at the same moment.
  perform pg_advisory_xact_lock(hashtext('friendsgiving_capacity'));

  if v_status = 'yes' then
    select coalesce(sum(1 + case when r.plus_one then 1 else 0 end), 0)
      into v_taken
      from public.rsvps r
     where r.status = 'yes';

    if v_taken + 1 + (case when coalesce(p_plus_one, false) then 1 else 0 end) > v_capacity then
      v_status := 'waitlist';
    end if;
  end if;

  insert into public.rsvps (name, status, plus_one, plus_one_name, dish_category, dish)
  values (
    trim(p_name),
    v_status,
    coalesce(p_plus_one, false) and v_status <> 'no',
    case when coalesce(p_plus_one, false) and v_status <> 'no' then nullif(trim(p_plus_one_name), '') end,
    case when v_status in ('yes', 'maybe') then nullif(p_dish_category, '') end,
    case when v_status in ('yes', 'maybe') then nullif(trim(p_dish), '') end
  )
  returning id into v_id;

  insert into public.rsvp_private (rsvp_id, phone, dietary)
  values (v_id, nullif(trim(p_phone), ''), nullif(trim(p_dietary), ''));

  return query select v_id, v_status;
end;
$$;

revoke all on function public.submit_rsvp(text, text, boolean, text, text, text, text, text) from public;
grant execute on function public.submit_rsvp(text, text, boolean, text, text, text, text, text) to anon, authenticated;

-- ---------- realtime ----------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rsvps'
  ) then
    alter publication supabase_realtime add table public.rsvps;
  end if;
end $$;
