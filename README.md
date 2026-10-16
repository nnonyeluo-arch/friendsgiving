# Potluck RSVP

A real-time RSVP page and potluck board for small events. Guests RSVP, claim a dish, and see the board update live on every screen, so nobody brings the fifth mac and cheese.

**[Live demo with sample data →](https://nnonyeluo-arch.github.io/friendsgiving/#demo)**

**Stack:** static HTML/CSS/JS on GitHub Pages · Supabase (Postgres, Row Level Security, Realtime) · no framework, no build step

## Features

- **RSVP** with yes / maybe / can't, plus-ones, phone, and dietary notes
- **Live potluck board** grouped by category (mains, sides, desserts, drinks). Categories still short on dishes are flagged.
- **Headcount cap** with an automatic waitlist once the event is full
- **Guest list** that separates confirmed, maybe, and waitlisted guests
- **Host notifications** pushed to a phone for every RSVP, through [ntfy](https://ntfy.sh)
- **Demo mode** (`#demo`) that runs on sample data and never writes to the database

## Architecture

```
Browser (GitHub Pages)
  │  read:  SELECT on rsvps          ──►  Postgres (RLS: public read)
  │  write: rpc('submit_rsvp')       ──►  SECURITY DEFINER function
  │                                         ├─ validates input
  │                                         ├─ advisory lock + capacity check
  │                                         ├─ insert rsvps (public)
  │                                         └─ insert rsvp_private (hosts only)
  └─ subscribe: postgres_changes     ◄──  Supabase Realtime
```

### Design decisions

- **The browser has a single write path.** The anonymous role can't insert, update, or delete rows directly. Every write goes through `submit_rsvp()`, which validates input and writes both tables in one transaction.
- **The capacity rule lives in the database.** The function takes a transaction-scoped advisory lock before counting confirmed guests (plus-ones included). Two people can't take the last spot at the same moment, and nothing in the client can get around the cap. Over-capacity "yes" responses are moved to `waitlist`.
- **Public and private data live in separate tables.** Names and dishes are in `rsvps`, which anyone can read. Phone numbers and dietary notes are in `rsvp_private`, which has RLS enabled and no policies, so it can only be read from the dashboard with the service role.
- **Guest text is rendered safely.** All user-supplied text reaches the DOM through `textContent`, never `innerHTML`.
- **Realtime has a fallback.** The board subscribes to Postgres changes, re-polls every 60 seconds, and refreshes when the tab regains focus, so it stays current if the WebSocket drops.

### Tested

The SQL was tested against a local Postgres 16 instance with the `anon` and `authenticated` roles: direct writes are rejected, the private table can't be read, invalid statuses are refused, the setup script is idempotent, and the cap holds at exactly 35 heads, with RSVP number 36 going to the waitlist.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | The whole front end: markup, styles, and script |
| `supabase/setup.sql` | Tables, RLS, `submit_rsvp()`, realtime publication. Safe to re-run. |
| `supabase/host-view.sql` | Host-only query that joins in phones and dietary notes |

## Run your own

1. Create a Supabase project and run `supabase/setup.sql` in the SQL Editor.
2. In `index.html`, set `SUPABASE_URL`, `SUPABASE_KEY` (the publishable key), and `CAPACITY`. Set the same capacity in `submit_rsvp()`.
3. Update the event details in the header.
4. Turn on GitHub Pages (deploy from `main`, root folder).

To reset between events, run `truncate table public.rsvp_private, public.rsvps;`.

---

Built by Nnonyelu Okafor.
