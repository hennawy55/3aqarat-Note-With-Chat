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
set search_path=public,realtime,pg_temp
as $$
declare
  row_data jsonb;
  target_room uuid;
  target_user uuid;
  target_users uuid[] := array[]::uuid[];
  session_row record;
begin
  if tg_op='DELETE' then row_data=to_jsonb(old); else row_data=to_jsonb(new); end if;
  if tg_table_name='chat_user_settings' then
    target_users=array[(row_data->>'user_id')::uuid];
  else
    if tg_table_name in ('chat_messages','chat_members') then
      target_room=(row_data->>'room_id')::uuid;
    elsif tg_table_name in ('chat_message_receipts','chat_message_reactions') then
      select room_id into target_room from public.chat_messages where id=(row_data->>'message_id')::uuid;
    end if;
    if target_room is not null then
      select array_agg(distinct user_id) into target_users from public.chat_members where room_id=target_room;
    end if;
    if tg_table_name='chat_members' and row_data ? 'user_id' then
      target_users=array_append(coalesce(target_users,array[]::uuid[]),(row_data->>'user_id')::uuid);
    end if;
  end if;
  foreach target_user in array coalesce(target_users,array[]::uuid[]) loop
    if target_user is not null then
      for session_row in
        select token_hash from public.auth_sessions
        where user_id=target_user and revoked_at is null and expires_at>now()
      loop
        perform realtime.send(
          jsonb_build_object('table',tg_table_name,'roomId',coalesce(target_room::text,'')),
          'chat_refresh',
          'smartnote-session:'||session_row.token_hash,
          false
        );
      end loop;
    end if;
  end loop;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.broadcast_smartnote_chat_change() from public,anon,authenticated;

drop trigger if exists smartnote_chat_messages_broadcast on public.chat_messages;
create trigger smartnote_chat_messages_broadcast
after insert or update or delete on public.chat_messages
for each row execute function public.broadcast_smartnote_chat_change();

drop trigger if exists smartnote_chat_members_broadcast on public.chat_members;
create trigger smartnote_chat_members_broadcast
after insert or update or delete on public.chat_members
for each row execute function public.broadcast_smartnote_chat_change();

drop trigger if exists smartnote_chat_receipts_broadcast on public.chat_message_receipts;
create trigger smartnote_chat_receipts_broadcast
after insert or update or delete on public.chat_message_receipts
for each row execute function public.broadcast_smartnote_chat_change();

drop trigger if exists smartnote_chat_reactions_broadcast on public.chat_message_reactions;
create trigger smartnote_chat_reactions_broadcast
after insert or update or delete on public.chat_message_reactions
for each row execute function public.broadcast_smartnote_chat_change();

-- Presence is intentionally polled at a low frequency to avoid broadcast feedback loops.
drop trigger if exists smartnote_chat_presence_broadcast on public.chat_presence;

drop trigger if exists smartnote_chat_settings_broadcast on public.chat_user_settings;
create trigger smartnote_chat_settings_broadcast
after insert or update or delete on public.chat_user_settings
for each row execute function public.broadcast_smartnote_chat_change();
