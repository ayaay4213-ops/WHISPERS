-- WHISPERS database proposal (review before deployment; not connected to a live database).
-- Adapt syntax and policies to the selected backend. Never expose service-role credentials to clients.

create table if not exists profiles (
  id uuid primary key,
  handle text unique not null,
  display_name text not null,
  avatar_url text,
  bio text default '',
  country text,
  status text not null default 'active' check (status in ('active','suspended','banned')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists rooms (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id),
  title text not null,
  topic text not null default 'عام',
  description text default '',
  is_private boolean not null default false,
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now()
);

create table if not exists room_members (
  room_id uuid not null references rooms(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'listener' check (role in ('owner','moderator','speaker','listener')),
  joined_at timestamptz not null default now(),
  primary key (room_id,user_id)
);

create table if not exists gifts (
  id text primary key,
  name_ar text not null,
  price_coins bigint not null check (price_coins > 0),
  is_active boolean not null default true
);

create table if not exists wallets (
  user_id uuid primary key references profiles(id) on delete cascade,
  balance_coins bigint not null default 0 check (balance_coins >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text unique not null,
  actor_user_id uuid references profiles(id),
  recipient_user_id uuid references profiles(id),
  room_id uuid references rooms(id),
  gift_id text references gifts(id),
  transaction_type text not null check (transaction_type in ('welcome_bonus','daily_reward','gift_sent','gift_received','admin_adjustment','purchase','refund')),
  amount_coins bigint not null check (amount_coins <> 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create table if not exists conversation_members (
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  primary key (conversation_id,user_id)
);
create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id uuid not null references profiles(id),
  body text not null check (length(body) between 1 and 5000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create table if not exists follows (
  follower_id uuid not null references profiles(id) on delete cascade,
  followed_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);
create table if not exists blocks (
  blocker_id uuid not null references profiles(id) on delete cascade,
  blocked_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references profiles(id),
  target_user_id uuid references profiles(id),
  room_id uuid references rooms(id),
  reason text not null,
  details text default '',
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  reviewed_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table if not exists agencies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references profiles(id),
  status text not null default 'pending' check (status in ('pending','approved','suspended','rejected')),
  created_at timestamptz not null default now()
);
create table if not exists agency_members (
  agency_id uuid not null references agencies(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null check (role in ('agent','host')),
  status text not null default 'pending' check (status in ('pending','approved','rejected','removed')),
  joined_at timestamptz not null default now(),
  primary key (agency_id,user_id)
);
create table if not exists payout_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency_code char(3) not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','paid','cancelled')),
  provider_reference text,
  reviewed_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);


-- Agency operations, hosts, and independent coin-shipping agents.
create table if not exists agency_settings (
  agency_id uuid primary key references agencies(id) on delete cascade,
  commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  monthly_host_target bigint not null default 0 check (monthly_host_target >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists host_activity (
  id uuid primary key default gen_random_uuid(),
  host_user_id uuid not null references profiles(id),
  agency_id uuid references agencies(id),
  room_id uuid references rooms(id),
  started_at timestamptz not null,
  ended_at timestamptz,
  minutes_active integer not null default 0 check (minutes_active >= 0),
  gifts_received_coins bigint not null default 0 check (gifts_received_coins >= 0),
  status text not null default 'recorded' check (status in ('recorded','reviewed','disputed'))
);

create table if not exists host_reward_rules (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid references agencies(id) on delete cascade,
  min_minutes integer not null default 0 check (min_minutes >= 0),
  min_gifts_coins bigint not null default 0 check (min_gifts_coins >= 0),
  reward_coins bigint not null check (reward_coins >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists shipping_agents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references profiles(id),
  display_business_name text not null,
  status text not null default 'pending' check (status in ('pending','approved','suspended','rejected')),
  commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  approved_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists coin_topup_orders (
  id uuid primary key default gen_random_uuid(),
  buyer_user_id uuid not null references profiles(id),
  shipping_agent_id uuid references shipping_agents(id),
  coins_requested bigint not null check (coins_requested > 0),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency_code char(3) not null,
  payment_reference text,
  status text not null default 'pending' check (status in ('pending','payment_submitted','approved','rejected','cancelled','credited')),
  reviewed_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  credited_at timestamptz
);

create table if not exists agency_applications (
  id uuid primary key default gen_random_uuid(),
  applicant_user_id uuid not null references profiles(id),
  proposed_name text not null,
  contact_details jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table if not exists admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references profiles(id),
  action text not null,
  target_type text not null,
  target_id text not null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- WHISPERS NOTE: shipping-agent approval and coin crediting must be server-side only.
-- Use idempotency keys and immutable audit records for every credit/refund.
-- IMPORTANT: Add row-level security/policies and server-only transaction procedures before production.
-- Never permit clients to insert arbitrary wallet ledger entries or update wallet balances directly.
