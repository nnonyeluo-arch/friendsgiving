# Friendsgiving 2026

RSVP page and live potluck board for a 35-person Friendsgiving. Guests RSVP, claim a dish, and watch the board update in real time, so nobody brings the fifth mac and cheese.

**Stack:** static HTML/CSS/JS on GitHub Pages · Supabase (Postgres + Realtime) · no build step

## How it works

- **Live board.** The page subscribes to Postgres changes over Supabase Realtime. When anyone RSVPs, every open browser re-renders the potluck board and the guest list. A 60-second poll and a refresh on tab focus cover dropped sockets.
- **One write path.** The browser can't insert, update, or delete rows directly. All writes go through `submit_rsvp()`, a `SECURITY DEFINER` Postgres function that validates input and writes both tables in one transaction.
- **Headcount cap in the database.** The function counts confirmed guests (plus-ones included) under an advisory transaction lock, so two people can't take the last spot at the same moment. Once the event is full, a "yes" lands on the waitlist automatically.
- **Public vs. private data.** `rsvps` (names, dishes) is readable by anyone with the link. `rsvp_private` (phone numbers, dietary notes) has RLS on and no policies, so only the hosts can read it, from the Supabase dashboard.
- **Safe to render.** Guest-entered text goes into the DOM through `textContent`, never `innerHTML`.
- **Host pings.** Each RSVP sends a push notification to the hosts through ntfy.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole front end |
| `supabase/setup.sql` | Tables, row-level security, `submit_rsvp()`, realtime publication. Safe to re-run. |
| `supabase/host-view.sql` | Hosts' full list with phones and dietary notes |

## Setup

1. Create a Supabase project and run `supabase/setup.sql` in the SQL Editor.
2. Put the project URL and publishable key at the top of the script in `index.html`.
3. Turn on GitHub Pages (deploy from `main`, root folder).

Add `#demo` to the URL to try the page with sample data and no database writes.
