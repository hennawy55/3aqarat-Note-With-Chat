-- Chat feature expansion: delivery/read receipts, replies, mentions, reactions,
-- per-room and global notification preferences, online presence and realtime signals.

alter table public.chat_members
  add column if not exists notifications_muted boolean not null default false;

alter table public.chat_messages
  add column if not exists reply_to_id uuid references public.chat_messages(id) on delete set null,
  add column if not exists mention_all boolean not null default false;

create table if not exists public.chat_message_receipts (
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id,user_id)
);
create index if not exists chat_receipts_user_unread_idx
  on public.chat_message_receipts(user_id,read_at) where read_at is null;

create table if not exists public.chat_message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (emoji in ('👍','❤️','😂','😮','😢','🙏')),
  created_at timestamptz not null default now(),
  unique(message_id,user_id,emoji)
);
create index if not exists chat_reactions_message_idx
  on public.chat_message_reactions(message_id,created_at);

create table if not exists public.chat_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_seen_at timestamptz not null default now()
);
create index if not exists chat_presence_recent_idx on public.chat_presence(last_seen_at desc);

create table if not exists public.chat_user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  mute_all boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.chat_message_receipts enable row level security;
alter table public.chat_message_reactions enable row level security;
alter table public.chat_presence enable row level security;
alter table public.chat_user_settings enable row level security;
revoke all on public.chat_message_receipts,public.chat_message_reactions,public.chat_presence,public.chat_user_settings from anon,authenticated;
grant all on public.chat_message_receipts,public.chat_message_reactions,public.chat_presence,public.chat_user_settings to service_role;

create or replace function public.broadcast_smartnote_chat_change()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  row_data jsonb;
  target_room text;
begin
  if tg_op='DELETE' then row_data=to_jsonb(old); else row_data=to_jsonb(new); end if;
  target_room=coalesce(row_data->>'room_id','');
  perform realtime.send(
    jsonb_build_object('table',tg_table_name,'roomId',target_room,'userId',coalesce(row_data->>'user_id','')),
    'chat_refresh',
    'smartnote-chat',
    false
  );
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists smartnote_chat_messages_broadcast on public.chat_messages;
create trigger smartnote_chat_messages_broadcast
after insert or update or delete on public.chat_messages
for each row execute function public.broadcast_smartnote_chat_change();

drop trigger if exists smartnote_chat_members_broadcast on public.chat_members;
create trigger smartnote_chat_members_broadcast
after insert or update or delete on public.chat_members
for each row execute function public.broadcast_smartnote_chat_change();

drop trigger if exists smartnote_chat_reactions_broadcast on public.chat_message_reactions;
create trigger smartnote_chat_reactions_broadcast
after insert or update or delete on public.chat_message_reactions
for each row execute function public.broadcast_smartnote_chat_change();

drop trigger if exists smartnote_chat_presence_broadcast on public.chat_presence;
create trigger smartnote_chat_presence_broadcast
after insert or update or delete on public.chat_presence
for each row execute function public.broadcast_smartnote_chat_change();

drop trigger if exists smartnote_chat_settings_broadcast on public.chat_user_settings;
create trigger smartnote_chat_settings_broadcast
after insert or update or delete on public.chat_user_settings
for each row execute function public.broadcast_smartnote_chat_change();
