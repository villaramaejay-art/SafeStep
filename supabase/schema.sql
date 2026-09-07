-- SafeStep database schema.
-- Run this once in the Supabase SQL Editor (Dashboard -> SQL Editor -> New query).
-- Safe to re-run: every statement is idempotent.

-- ---------------------------------------------------------------------------
-- Account profiles
--
-- auth.users only stores the email and password. The details collected on the
-- registration form live here, one row per account.
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  first_name text not null check (length(trim(first_name)) >= 2),
  last_name  text not null check (length(trim(last_name)) >= 2),
  phone      text not null check (length(trim(phone)) >= 7),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles are private" on public.profiles;
create policy "profiles are private"
  on public.profiles
  for all
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- The app passes first_name/last_name/phone as sign-up metadata; this copies
-- them into profiles inside the same transaction that creates the account, so
-- an account can never exist without its details.
create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Sign-ups without this metadata (for example anonymous sessions) are left
  -- alone rather than failing the CHECK constraints.
  if new.raw_user_meta_data ? 'first_name' then
    insert into public.profiles (id, first_name, last_name, phone)
    values (
      new.id,
      trim(new.raw_user_meta_data ->> 'first_name'),
      trim(new.raw_user_meta_data ->> 'last_name'),
      trim(new.raw_user_meta_data ->> 'phone')
    )
    on conflict (id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute function public.create_profile_for_new_user();

-- ---------------------------------------------------------------------------
-- Emergency contacts
-- ---------------------------------------------------------------------------

create table if not exists public.contacts (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  full_name    text not null check (length(trim(full_name)) >= 2),
  phone        text not null check (length(trim(phone)) >= 7),
  relationship text not null check (
    relationship in ('father', 'mother', 'sister', 'spouse', 'friend', 'partner')
  ),
  priority     text not null default 'secondary' check (
    priority in ('primary', 'secondary')
  ),
  created_at   timestamptz not null default now()
);

create index if not exists contacts_user_id_idx
  on public.contacts (user_id, created_at);

-- A user may keep only one primary contact. Enforced in the database so the
-- rule holds no matter which client writes the row.
create or replace function public.demote_other_primary_contacts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.priority = 'primary' then
    update public.contacts
       set priority = 'secondary'
     where user_id = new.user_id
       and id <> new.id
       and priority = 'primary';
  end if;
  return new;
end;
$$;

-- The inner UPDATE re-fires this trigger, but sets priority to 'secondary',
-- so the branch above is skipped and the recursion stops immediately.
drop trigger if exists contacts_single_primary on public.contacts;
create trigger contacts_single_primary
  after insert or update of priority on public.contacts
  for each row execute function public.demote_other_primary_contacts();

-- ---------------------------------------------------------------------------
-- Safe spaces
-- ---------------------------------------------------------------------------

create table if not exists public.safe_spaces (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null check (length(trim(name)) > 0),
  latitude   double precision not null check (latitude between -90 and 90),
  longitude  double precision not null check (longitude between -180 and 180),
  radius_km  double precision not null check (radius_km between 0.1 and 0.5),
  is_custom  boolean not null default true,
  created_at timestamptz not null default now()
);

-- Safe spaces once allowed up to 10 km, which covers a whole town: leaving a
-- zone that size says almost nothing about whether the user is in trouble.
-- Existing rows are brought into the range the app can now show, then the
-- limits are enforced here so no client can widen them again.
update public.safe_spaces set radius_km = 0.5 where radius_km > 0.5;
update public.safe_spaces set radius_km = 0.1 where radius_km < 0.1;

alter table public.safe_spaces drop constraint if exists safe_spaces_radius_km_check;
alter table public.safe_spaces add constraint safe_spaces_radius_km_check
  check (radius_km between 0.1 and 0.5);

create index if not exists safe_spaces_user_id_idx
  on public.safe_spaces (user_id, created_at);

-- Names are compared case-insensitively in the app, so enforce the same here.
create unique index if not exists safe_spaces_user_name_idx
  on public.safe_spaces (user_id, lower(name));

-- ---------------------------------------------------------------------------
-- Alert log
--
-- Every SMS the app sends is recorded here, so there is a record of what went
-- out even though the message itself is sent from the handset.
-- ---------------------------------------------------------------------------

create table if not exists public.alerts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  reason        text not null check (
    reason in ('panic', 'timer_expired', 'left_safe_space', 'all_clear')
  ),
  message       text not null,
  recipients    integer not null default 0,
  delivered     integer not null default 0,
  latitude      double precision,
  longitude     double precision,
  safe_space    text,
  created_at    timestamptz not null default now()
);

-- `create table if not exists` leaves an existing table untouched, so the
-- 'all_clear' reason has to be added separately for projects created before the
-- stand-down message existed.
alter table public.alerts drop constraint if exists alerts_reason_check;
alter table public.alerts add constraint alerts_reason_check check (
  reason in ('panic', 'timer_expired', 'left_safe_space', 'all_clear')
);

-- Why a send failed, when it did. Without it the history can say a message
-- was not delivered but not what the network objected to, and the reason is
-- gone the moment the confirmation disappears.
alter table public.alerts add column if not exists failure text;

create index if not exists alerts_user_id_idx
  on public.alerts (user_id, created_at desc);

alter table public.alerts enable row level security;

drop policy if exists "alerts are private" on public.alerts;
create policy "alerts are private"
  on public.alerts
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Row level security: a user only ever sees their own rows
-- ---------------------------------------------------------------------------

alter table public.contacts     enable row level security;
alter table public.safe_spaces  enable row level security;

drop policy if exists "contacts are private" on public.contacts;
create policy "contacts are private"
  on public.contacts
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "safe spaces are private" on public.safe_spaces;
create policy "safe spaces are private"
  on public.safe_spaces
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- No default safe spaces
--
-- New accounts used to be seeded with Home/Work/Gym at fixed Metro Manila
-- coordinates. That was wrong: a safe space is a place the user has actually
-- chosen, and a zone nobody set is a zone nobody can be alerted about
-- meaningfully. An account now starts empty and the user adds their own.
-- ---------------------------------------------------------------------------

drop trigger if exists on_auth_user_created_seed_safe_spaces on auth.users;
drop function if exists public.seed_default_safe_spaces();

-- Removes the seeds already handed to existing accounts.
--
-- Only the old trigger ever wrote is_custom = false; every safe space saved
-- through the app is true. So this deletes exactly the three defaults and
-- nothing the user created, and re-running it later deletes nothing.
delete from public.safe_spaces where is_custom = false;
