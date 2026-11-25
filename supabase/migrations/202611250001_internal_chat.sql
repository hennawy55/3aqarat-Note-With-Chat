-- Internal SmartNote chat schema. All data access is mediated by the authenticated Edge Function.
create table if not exists public.chat_rooms (
 id uuid primary key default gen_random_uuid(),
 room_type text not null check (room_type in ('public','private','group')),
 name text not null default '',
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists chat_one_public_room_idx on public.chat_rooms(room_type) where room_type='public';
create table if not exists public.chat_members (
 room_id uuid not null references public.chat_rooms(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 member_role text not null default 'member' check (member_role in ('owner','member')),
 joined_at timestamptz not null default now(),
 last_read_at timestamptz,
 primary key(room_id,user_id)
);
create index if not exists chat_members_user_idx on public.chat_members(user_id,joined_at desc);
create table if not exists public.chat_messages (
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.chat_rooms(id) on delete cascade,
 sender_id uuid not null references public.profiles(id),
 body text not null check (length(trim(body)) between 1 and 5000),
 created_at timestamptz not null default now()
);
create index if not exists chat_messages_room_timeline_idx on public.chat_messages(room_id,created_at desc,id desc);
alter table public.chat_rooms enable row level security;
alter table public.chat_members enable row level security;
alter table public.chat_messages enable row level security;
revoke all on public.chat_rooms,public.chat_members,public.chat_messages from anon,authenticated;
grant all on public.chat_rooms,public.chat_members,public.chat_messages to service_role;
