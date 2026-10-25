-- Back to Our Childhood
-- Supabase/PostgreSQL migration
-- Run this entire file in Supabase SQL Editor.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 40),
  username text unique check (username is null or username ~ '^[a-zA-Z0-9_]{3,24}$'),
  avatar text not null default '🧒🏾' check (char_length(avatar) between 1 and 12),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.game_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text not null unique check (room_code ~ '^[A-Z0-9]{6}$'),
  game_type text not null check (game_type in ('ten_ten','name_animal_place_and_thing','ayo')),
  host_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'waiting' check (status in ('waiting','starting','playing','paused','finished','cancelled')),
  max_players integer not null default 2 check (max_players between 2 and 8),
  current_round integer not null default 0 check (current_round >= 0),
  game_state jsonb not null default '{}'::jsonb,
  is_private boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  started_at timestamptz,
  ended_at timestamptz
);

create table if not exists public.room_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_host boolean not null default false,
  is_ready boolean not null default false,
  score integer not null default 0 check (score >= 0),
  player_status text not null default 'connected' check (player_status in ('connected','disconnected','left','eliminated','finished')),
  joined_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now()),
  unique(room_id, user_id)
);

create table if not exists public.game_sessions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  game_type text not null check (game_type in ('ten_ten','name_animal_place_and_thing','ayo')),
  round_number integer not null default 1 check (round_number > 0),
  current_player_id uuid references public.room_players(id) on delete set null,
  game_state jsonb not null default '{}'::jsonb,
  scores jsonb not null default '{}'::jsonb,
  turn_started_at timestamptz,
  turn_ends_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.game_moves (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.game_sessions(id) on delete cascade,
  player_id uuid not null references public.room_players(id) on delete cascade,
  move_type text not null check (char_length(trim(move_type)) between 1 and 50),
  move_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 500),
  is_published boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.achievements (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text not null,
  icon text not null default '🏆',
  requirement_type text not null,
  requirement_value integer not null default 1 check (requirement_value > 0),
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.user_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id uuid not null references public.achievements(id) on delete cascade,
  earned_at timestamptz not null default timezone('utc', now()),
  unique(user_id, achievement_id)
);

create table if not exists public.game_results (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  game_session_id uuid not null references public.game_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  final_score integer not null default 0 check (final_score >= 0),
  position integer not null check (position > 0),
  result text not null check (result in ('win','loss','draw')),
  completed_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_game_rooms_status on public.game_rooms(status);
create index if not exists idx_game_rooms_game_type on public.game_rooms(game_type);
create index if not exists idx_room_players_room on public.room_players(room_id);
create index if not exists idx_room_players_user on public.room_players(user_id);
create index if not exists idx_room_players_last_seen on public.room_players(last_seen_at);
create index if not exists idx_game_sessions_room on public.game_sessions(room_id);
create index if not exists idx_game_moves_session on public.game_moves(session_id, created_at);
create index if not exists idx_memories_published on public.memories(is_published, created_at desc);
create index if not exists idx_game_results_user on public.game_results(user_id);
create index if not exists idx_game_results_game on public.game_results(game_session_id);

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists rooms_updated_at on public.game_rooms;
create trigger rooms_updated_at before update on public.game_rooms
for each row execute function public.set_updated_at();

drop trigger if exists sessions_updated_at on public.game_sessions;
create trigger sessions_updated_at before update on public.game_sessions
for each row execute function public.set_updated_at();

drop trigger if exists memories_updated_at on public.memories;
create trigger memories_updated_at before update on public.memories
for each row execute function public.set_updated_at();

-- Create a profile automatically after sign-up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, username, avatar)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), 'Player'),
    nullif(trim(new.raw_user_meta_data->>'username'), ''),
    coalesce(nullif(new.raw_user_meta_data->>'avatar', ''), '🧒🏾')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Room code generator.
create or replace function public.generate_room_code()
returns text
language plpgsql
as $$
declare
  candidate text;
begin
  loop
    candidate := upper(substr(encode(gen_random_bytes(6), 'base64'), 1, 6));
    candidate := regexp_replace(candidate, '[^A-Z0-9]', 'A', 'g');
    exit when length(candidate) = 6
      and not exists (select 1 from public.game_rooms where room_code = candidate);
  end loop;
  return candidate;
end;
$$;

-- Authorization helpers.
create or replace function public.is_room_member(p_room_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.room_players
    where room_id = p_room_id
      and user_id = auth.uid()
      and player_status <> 'left'
  );
$$;

create or replace function public.is_room_host(p_room_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.game_rooms
    where id = p_room_id
      and host_id = auth.uid()
  );
$$;

-- Room creation is performed server-side so host/user fields cannot be spoofed.
create or replace function public.create_room(
  p_game_type text,
  p_max_players integer default 2,
  p_is_private boolean default false
)
returns public.game_rooms
language plpgsql
security definer set search_path = public
as $$
declare
  r public.game_rooms;
  code text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_game_type not in ('ten_ten','name_animal_place_and_thing','ayo') then
    raise exception 'Unsupported game';
  end if;
  if p_max_players < 2 or p_max_players > 8 then
    raise exception 'Player limit must be between 2 and 8';
  end if;

  code := public.generate_room_code();

  insert into public.game_rooms(room_code, game_type, host_id, max_players, is_private)
  values (code, p_game_type, auth.uid(), p_max_players, p_is_private)
  returning * into r;

  insert into public.room_players(room_id, user_id, is_host, is_ready)
  values (r.id, auth.uid(), true, true);

  return r;
end;
$$;

-- Join is atomic and validates the room before insertion.
create or replace function public.join_room(p_room_code text)
returns public.room_players
language plpgsql
security definer set search_path = public
as $$
declare
  r public.game_rooms;
  rp public.room_players;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select * into r from public.game_rooms
  where room_code = upper(trim(p_room_code))
  for update;

  if not found then raise exception 'Room not found'; end if;
  if r.status <> 'waiting' then raise exception 'This room is no longer accepting players'; end if;

  if exists (
    select 1 from public.room_players
    where room_id = r.id and user_id = auth.uid() and player_status <> 'left'
  ) then
    select * into rp from public.room_players
    where room_id = r.id and user_id = auth.uid();
    return rp;
  end if;

  if (select count(*) from public.room_players where room_id = r.id and player_status <> 'left') >= r.max_players then
    raise exception 'Room is full';
  end if;

  insert into public.room_players(room_id, user_id, is_host, is_ready)
  values (r.id, auth.uid(), false, false)
  returning * into rp;

  return rp;
end;
$$;

create or replace function public.set_ready(p_room_id uuid, p_ready boolean)
returns public.room_players
language plpgsql
security definer set search_path = public
as $$
declare rp public.room_players;
begin
  update public.room_players
  set is_ready = p_ready, last_seen_at = timezone('utc', now()), player_status = 'connected'
  where room_id = p_room_id and user_id = auth.uid() and player_status <> 'left'
  returning * into rp;
  if not found then raise exception 'Room membership not found'; end if;
  return rp;
end;
$$;

-- Host starts a room and creates its first authoritative game session.
create or replace function public.start_room(p_room_id uuid)
returns public.game_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  r public.game_rooms;
  s public.game_sessions;
  first_player uuid;
begin
  if not public.is_room_host(p_room_id) then raise exception 'Only the host can start the room'; end if;

  select * into r from public.game_rooms where id = p_room_id for update;
  if r.status <> 'waiting' then raise exception 'Room is not waiting'; end if;

  if (select count(*) from public.room_players where room_id = r.id and player_status <> 'left') < 2 then
    raise exception 'At least two players are required';
  end if;

  if exists (
    select 1 from public.room_players
    where room_id = r.id and player_status <> 'left' and not is_ready
  ) then
    raise exception 'All active players must be ready';
  end if;

  select id into first_player from public.room_players
  where room_id = r.id and player_status <> 'left'
  order by joined_at asc limit 1;

  update public.game_rooms
  set status = 'playing', current_round = 1, started_at = timezone('utc', now())
  where id = r.id;

  insert into public.game_sessions(
    room_id, game_type, round_number, current_player_id, game_state, scores
  )
  values (
    r.id, r.game_type, 1, first_player,
    case
      when r.game_type = 'ayo' then
        '{"board":[4,4,4,4,4,4,4,4,4,4,4,4],"captured":{"p1":0,"p2":0},"status":"playing"}'::jsonb
      when r.game_type = 'name_animal_place_and_thing' then
        '{"status":"playing","letter":null,"submissions":{},"submitted":{}}'::jsonb
      else
        '{"status":"playing","round":1,"action":"awaiting_action"}'::jsonb
    end,
    '{}'::jsonb
  )
  returning * into s;

  return s;
end;
$$;

create or replace function public.heartbeat_room(p_room_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.room_players
  set last_seen_at = timezone('utc', now()), player_status = 'connected'
  where room_id = p_room_id and user_id = auth.uid() and player_status <> 'left';
  if not found then raise exception 'Room membership not found'; end if;
end;
$$;

create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare leaving_host boolean;
begin
  select is_host into leaving_host from public.room_players
  where room_id = p_room_id and user_id = auth.uid() and player_status <> 'left';

  if leaving_host is null then raise exception 'Room membership not found'; end if;

  update public.room_players
  set player_status = 'left', is_ready = false, last_seen_at = timezone('utc', now())
  where room_id = p_room_id and user_id = auth.uid();

  if leaving_host then
    if exists(select 1 from public.room_players where room_id = p_room_id and player_status <> 'left') then
      update public.room_players
      set is_host = true
      where id = (
        select id from public.room_players
        where room_id = p_room_id and player_status <> 'left'
        order by joined_at asc limit 1
      );
      update public.game_rooms
      set host_id = (select user_id from public.room_players where room_id = p_room_id and is_host = true limit 1)
      where id = p_room_id and status = 'waiting';
    else
      update public.game_rooms set status = 'cancelled', ended_at = timezone('utc', now())
      where id = p_room_id and status in ('waiting','starting');
    end if;
  end if;
end;
$$;

create or replace function public.submit_game_move(
  p_session_id uuid,
  p_move_type text,
  p_move_data jsonb
)
returns public.game_moves
language plpgsql
security definer set search_path = public
as $$
declare
  s public.game_sessions;
  rp public.room_players;
  m public.game_moves;
begin
  select * into s from public.game_sessions where id = p_session_id for update;
  if not found then raise exception 'Game session not found'; end if;

  select * into rp from public.room_players
  where room_id = s.room_id and user_id = auth.uid() and player_status <> 'left';
  if not found then raise exception 'You are not in this room'; end if;

  if s.game_state->>'status' <> 'playing' then raise exception 'Game is not active'; end if;
  if s.turn_ends_at is not null and timezone('utc', now()) > s.turn_ends_at then
    raise exception 'Turn has expired';
  end if;

  -- For turn-based games, enforce the current player.
  if s.game_type in ('ayo','ten_ten') and s.current_player_id is distinct from rp.id then
    raise exception 'It is not your turn';
  end if;

  insert into public.game_moves(session_id, player_id, move_type, move_data)
  values (p_session_id, rp.id, trim(p_move_type), coalesce(p_move_data, '{}'::jsonb))
  returning * into m;

  return m;
end;
$$;

-- Ayo move: 12 pits, players own opposite sides. Seed-sowing is performed here.
create or replace function public.make_ayo_move(p_session_id uuid, p_pit integer)
returns public.game_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  s public.game_sessions;
  rp public.room_players;
  b integer[];
  seeds integer;
  idx integer;
  own_side boolean;
  next_player uuid;
  next_state jsonb;
begin
  select * into s from public.game_sessions where id = p_session_id for update;
  if not found or s.game_type <> 'ayo' then raise exception 'Not an Ayo session'; end if;

  select * into rp from public.room_players
  where room_id = s.room_id and user_id = auth.uid() and player_status <> 'left';
  if not found then raise exception 'You are not in this room'; end if;
  if s.current_player_id is distinct from rp.id then raise exception 'It is not your turn'; end if;
  if p_pit < 0 or p_pit > 11 then raise exception 'Invalid pit'; end if;

  b := array(
    select jsonb_array_elements_text(s.game_state->'board')::integer
  );

  -- Determine ownership by player order: first player owns pits 0-5, second owns 6-11.
  own_side := case
    when rp.id = (select current_player_id from public.game_sessions where id=p_session_id)
      then true else false end;
  -- The session stores the actual current player, so ownership is derived from room order.
  if p_pit <= 5 then
    if rp.id <> (select id from public.room_players where room_id=s.room_id and player_status <> 'left' order by joined_at asc limit 1)
      then raise exception 'Choose a pit on your side'; end if;
  else
    if rp.id <> (select id from public.room_players where room_id=s.room_id and player_status <> 'left' order by joined_at asc offset 1 limit 1)
      then raise exception 'Choose a pit on your side'; end if;
  end if;

  seeds := b[p_pit+1];
  if seeds <= 0 then raise exception 'That pit is empty'; end if;
  b[p_pit+1] := 0;
  idx := p_pit;

  while seeds > 0 loop
    idx := (idx + 1) % 12;
    b[idx+1] := b[idx+1] + 1;
    seeds := seeds - 1;
  end loop;

  next_player := (
    select id from public.room_players
    where room_id=s.room_id and player_status <> 'left'
    order by joined_at asc
    offset case
      when rp.id = (select id from public.room_players where room_id=s.room_id and player_status <> 'left' order by joined_at asc limit 1) then 1 else 0 end
    limit 1
  );

  next_state := jsonb_build_object(
    'status','playing',
    'board',to_jsonb(b),
    'captured',coalesce(s.game_state->'captured','{"p1":0,"p2":0}'::jsonb),
    'lastPit',idx,
    'lastMoveBy',rp.id
  );

  update public.game_sessions
  set game_state=next_state, current_player_id=next_player
  where id=p_session_id
  returning * into s;

  insert into public.game_moves(session_id, player_id, move_type, move_data)
  values (p_session_id, rp.id, 'ayo_pit', jsonb_build_object('pit',p_pit));

  return s;
end;
$$;

-- NAPT round finalization. This scores non-empty unique answers; category
-- semantics can be upgraded later with a dictionary/Edge Function.
create or replace function public.finalize_napt_round(p_session_id uuid)
returns public.game_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  s public.game_sessions;
  player record;
  answers jsonb;
  score integer;
  new_scores jsonb := '{}'::jsonb;
begin
  select * into s from public.game_sessions where id=p_session_id for update;
  if not found or s.game_type <> 'name_animal_place_and_thing' then
    raise exception 'Not a Name, Animal, Place and Thing session';
  end if;

  if s.game_state->>'status' <> 'playing' then raise exception 'Round already closed'; end if;

  for player in
    select rp.id, rp.user_id
    from public.room_players rp
    where rp.room_id=s.room_id and rp.player_status <> 'left'
  loop
    answers := coalesce(s.game_state->'submissions'->player.id::text, '{}'::jsonb);
    score := 0;
    if length(trim(coalesce(answers->>'name',''))) > 0 then score := score + 10; end if;
    if length(trim(coalesce(answers->>'animal',''))) > 0 then score := score + 10; end if;
    if length(trim(coalesce(answers->>'place',''))) > 0 then score := score + 10; end if;
    if length(trim(coalesce(answers->>'thing',''))) > 0 then score := score + 10; end if;
    new_scores := jsonb_set(new_scores, array[player.id::text], to_jsonb(score), true);
  end loop;

  update public.game_sessions
  set scores = new_scores,
      game_state = jsonb_set(s.game_state, '{status}', '"round_complete"'::jsonb)
  where id=p_session_id
  returning * into s;

  return s;
end;
$$;

-- Public leaderboard view: only aggregates real stored results.
create or replace view public.leaderboard as
select
  p.id as user_id,
  p.display_name,
  p.avatar,
  count(gr.id)::integer as games_played,
  count(*) filter (where gr.result='win')::integer as wins,
  coalesce(sum(gr.final_score),0)::integer as total_score
from public.profiles p
left join public.game_results gr on gr.user_id=p.id
group by p.id, p.display_name, p.avatar;

-- Seed achievements. These are definitions, not fake user achievements.
insert into public.achievements(name,description,icon,requirement_type,requirement_value)
values
 ('First Game','Complete your first game.','🎮','games_played',1),
 ('First Win','Win your first game.','🏆','wins',1),
 ('5 Games Played','Complete five games.','⭐','games_played',5),
 ('10 Games Won','Win ten games.','👑','wins',10),
 ('Childhood Champion','Win 25 games.','🥇','wins',25),
 ('Memory Keeper','Publish your first childhood memory.','📖','memories_published',1)
on conflict (name) do nothing;

-- RLS
alter table public.profiles enable row level security;
alter table public.game_rooms enable row level security;
alter table public.room_players enable row level security;
alter table public.game_sessions enable row level security;
alter table public.game_moves enable row level security;
alter table public.memories enable row level security;
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
alter table public.game_results enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
for select to authenticated
using (true);

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
for insert to authenticated
with check (id = auth.uid());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists rooms_select on public.game_rooms;
create policy rooms_select on public.game_rooms
for select to authenticated
using (public.is_room_member(id) or (status='waiting' and is_private=false));

drop policy if exists room_players_select on public.room_players;
create policy room_players_select on public.room_players
for select to authenticated
using (public.is_room_member(room_id));

drop policy if exists room_players_update_own on public.room_players;
create policy room_players_update_own on public.room_players
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists sessions_select on public.game_sessions;
create policy sessions_select on public.game_sessions
for select to authenticated
using (public.is_room_member(room_id));

drop policy if exists moves_select on public.game_moves;
create policy moves_select on public.game_moves
for select to authenticated
using (exists (
  select 1 from public.game_sessions s
  where s.id=game_moves.session_id and public.is_room_member(s.room_id)
));

drop policy if exists memories_public_read on public.memories;
create policy memories_public_read on public.memories
for select to anon, authenticated
using (is_published=true or user_id=auth.uid());

drop policy if exists memories_insert_own on public.memories;
create policy memories_insert_own on public.memories
for insert to authenticated
with check (user_id=auth.uid());

drop policy if exists memories_update_own on public.memories;
create policy memories_update_own on public.memories
for update to authenticated
using (user_id=auth.uid())
with check (user_id=auth.uid());

drop policy if exists memories_delete_own on public.memories;
create policy memories_delete_own on public.memories
for delete to authenticated
using (user_id=auth.uid());

drop policy if exists achievements_read on public.achievements;
create policy achievements_read on public.achievements
for select to anon, authenticated
using (true);

drop policy if exists user_achievements_read on public.user_achievements;
create policy user_achievements_read on public.user_achievements
for select to authenticated
using (user_id=auth.uid());

drop policy if exists results_read on public.game_results;
create policy results_read on public.game_results
for select to authenticated
using (true);

-- No direct client INSERT/UPDATE/DELETE policies are created for:
-- game_rooms, game_sessions, game_moves, game_results, user_achievements.
-- Mutations must go through the SECURITY DEFINER functions above or future
-- server-side Edge Functions.

grant execute on function public.create_room(text,integer,boolean) to authenticated;
grant execute on function public.join_room(text) to authenticated;
grant execute on function public.set_ready(uuid,boolean) to authenticated;
grant execute on function public.start_room(uuid) to authenticated;
grant execute on function public.heartbeat_room(uuid) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;
grant execute on function public.submit_game_move(uuid,text,jsonb) to authenticated;
grant execute on function public.make_ayo_move(uuid,integer) to authenticated;
grant execute on function public.finalize_napt_round(uuid) to authenticated;

-- Realtime publication. Ignore already-added tables.
do $$
declare
  t text;
begin
  foreach t in array array[
    'game_rooms','room_players','game_sessions','game_moves','memories'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime'
        and schemaname='public'
        and tablename=t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
