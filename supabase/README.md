# Back to Our Childhood — Supabase backend

This project keeps the original editable HTML/CSS/JavaScript frontend and adds a real Supabase backend.

## What is connected

- Supabase Authentication
- PostgreSQL schema
- Profiles
- Secure room creation/joining
- Room lobby membership and ready state
- Supabase Realtime subscriptions
- Heartbeat/reconnect support
- Secure RPCs for room lifecycle
- Game-session and move audit trail
- Ayo server-side move validation
- Name, Animal, Place and Thing submission/finalization architecture
- Ten-Ten server move endpoint
- Memory Wall storage
- Real leaderboard view
- Achievement definitions

## Important

The project is **configuration-dependent** until you create your Supabase project and paste its URL and publishable key into:

`js/supabase-config.js`

The browser must only receive the publishable/anon key. Never put a service-role key in this project.

## 1. Create Supabase

1. Create a Supabase project.
2. Open the project's SQL Editor.
3. Open `supabase/schema.sql` from this folder.
4. Paste the entire file into the SQL Editor.
5. Run it.
6. Confirm the tables, functions and RLS policies were created.

## 2. Add your client credentials

Open:

`js/supabase-config.js`

Replace:

```js
url: "YOUR_SUPABASE_URL",
publishableKey: "YOUR_SUPABASE_PUBLISHABLE_KEY"
```

with the values shown in your Supabase project's API settings.

Do not add a service-role/secret key.

## 3. Authentication settings

For the first test, email/password authentication is enough.

In Supabase Authentication settings:

- enable Email provider
- configure your site's allowed URL/redirect URL
- use your deployed site's URL for production

For password recovery, make sure the recovery redirect points back to your site.

## 4. Run locally

Because the site uses JavaScript modules and the Supabase client, use a small local web server rather than opening the HTML file with `file://`.

In VS Code, the easiest option is the Live Server extension.

Or, if Python is installed:

```bash
python -m http.server 5500
```

Then open:

`http://localhost:5500`

## 5. Test accounts

Create two different accounts. Use two browser windows/devices.

1. Sign up on Device A.
2. Sign up on Device B.
3. Give each player a different display name/avatar.
4. Create a room on Device A.
5. Copy the room code.
6. Join it from Device B.
7. Mark both players Ready.
8. Start from the host device.
9. Watch the room/session state update without refresh.

## 6. Room links and WhatsApp

Room links use a URL fragment:

`#join=ROOMCODE`

The frontend can copy the room link or open a WhatsApp share URL. No WhatsApp Business API is needed just to share an invite.

## 7. Security model

Direct client writes are intentionally restricted.

The important room operations use PostgreSQL functions:

- `create_room`
- `join_room`
- `set_ready`
- `start_room`
- `heartbeat_room`
- `leave_room`

Game actions use server-side RPCs:

- `submit_game_move`
- `make_ayo_move`
- `finalize_napt_round`

RLS prevents a normal authenticated client from directly changing game sessions, game moves, results, achievements, or another user's profile.

## 8. Game status

Launch game identifiers:

- `ten_ten`
- `name_animal_place_and_thing`
- `ayo`

The remaining games stay Coming Soon.

The existing frontend's local mini-game behavior is deliberately preserved. The backend modules provide the online architecture; an online game screen should call the matching module only after a real room/session exists.

## 9. Production hardening before launch

Before public launch, add:

- email verification policy
- abuse/rate limiting
- server-side moderation for memories
- a stronger NAPT dictionary/semantic answer validator
- authoritative Ten-Ten rules
- complete Ayo capture/end-game rules for your chosen Nigerian ruleset
- room expiry cleanup job
- achievement awarding transaction
- final-results transaction
- monitoring/error reporting
- privacy policy and terms

Do not advertise a game as fully online multiplayer until its server-side rules and result transaction are complete.

## 10. Testing checklist

### Accounts
- [ ] Sign up
- [ ] Sign in
- [ ] Sign out
- [ ] Password recovery
- [ ] Update profile
- [ ] Display name/avatar persist

### Rooms
- [ ] Create room
- [ ] Unique 6-character code
- [ ] Join room
- [ ] Invalid code rejected
- [ ] Full room rejected
- [ ] Duplicate join does not create duplicate membership
- [ ] Leave room
- [ ] Host transfer while waiting
- [ ] Empty room cancellation

### Realtime
- [ ] Player joins on Device B and appears on Device A
- [ ] Ready state updates without refresh
- [ ] Room status updates without refresh
- [ ] Game session appears after host starts
- [ ] Session changes arrive without refresh
- [ ] Heartbeat/reconnect works

### Security
- [ ] A user cannot update another user's profile
- [ ] A user cannot directly update another player's score
- [ ] A user cannot make themselves host
- [ ] A user cannot submit another player's move
- [ ] A user cannot move after turn expiry
- [ ] A user cannot access a private room unless they are a member

### Game rules
- [ ] Ayo rejects invalid pits
- [ ] Ayo rejects moves from the wrong player
- [ ] NAPT submissions are immutable after round closure
- [ ] Ten-Ten actions require the active player's turn
- [ ] Final results come from server/database logic, not browser-supplied scores
