-- Enforce one reaction per user on each message.
-- Keep the most recently selected reaction if older data contains duplicates.
with ranked as (
  select ctid,
         row_number() over (
           partition by message_id, user_id
           order by created_at desc, id desc
         ) as position
  from public.chat_message_reactions
)
delete from public.chat_message_reactions r
using ranked d
where r.ctid = d.ctid
  and d.position > 1;

create unique index if not exists chat_message_reactions_one_per_user_idx
  on public.chat_message_reactions(message_id, user_id);
