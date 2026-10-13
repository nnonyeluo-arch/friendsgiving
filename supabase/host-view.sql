-- Hosts only: the full list with phone numbers and dietary notes.
-- Run in Supabase → SQL Editor. (The website can't see this data.)
select
  r.created_at at time zone 'America/Chicago' as rsvp_time,
  r.name,
  r.status,
  case when r.plus_one then coalesce(r.plus_one_name, '+1') end as plus_one,
  r.dish_category,
  r.dish,
  p.phone,
  p.dietary
from public.rsvps r
left join public.rsvp_private p on p.rsvp_id = r.id
order by
  array_position(array['yes', 'maybe', 'waitlist', 'no'], r.status),
  r.created_at;

-- Headcount check
-- select sum(1 + case when plus_one then 1 else 0 end) as confirmed_heads
-- from public.rsvps where status = 'yes';

-- Remove a duplicate or test RSVP (deletes the private row too)
-- delete from public.rsvps where id = '<paste id>';
