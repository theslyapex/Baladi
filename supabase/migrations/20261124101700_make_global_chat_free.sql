-- Public chat is free for all authenticated players.
-- Existing profiles are normalized for compatibility with older client builds.
update public.baladi_game_profiles
set chat_unlocked_at = coalesce(chat_unlocked_at, now())
where chat_unlocked_at is null;

create or replace function public.baladi_send_global_message(
  p_user_id uuid,
  p_body text default null,
  p_sticker_id text default null
)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_profile public.baladi_game_profiles%rowtype;
  v_message public.baladi_global_chat_messages%rowtype;
  v_body text := nullif(btrim(coalesce(p_body, '')), '');
  v_last timestamptz;
begin
  select * into v_profile from public.baladi_game_profiles where user_id = p_user_id for update;
  if not found then raise exception 'پروفایل بازی پیدا نشد.'; end if;
  if p_sticker_id is null then
    if v_body is null or char_length(v_body) > 350 then raise exception 'پیام باید بین ۱ تا ۳۵۰ نویسه باشد.'; end if;
  else
    if v_body is not null then raise exception 'ارسال متن و استیکر هم‌زمان مجاز نیست.'; end if;
    if not exists (select 1 from public.baladi_cosmetic_catalog where id = p_sticker_id and kind = 'sticker' and is_active = true) then raise exception 'استیکر معتبر نیست.'; end if;
    if not exists (select 1 from public.baladi_user_cosmetics where user_id = p_user_id and cosmetic_id = p_sticker_id) then raise exception 'ابتدا باید این استیکر را بخری.'; end if;
  end if;
  select created_at into v_last from public.baladi_global_chat_messages where user_id = p_user_id and deleted_at is null order by created_at desc limit 1;
  if v_last is not null and v_last > now() - interval '2 seconds' then raise exception 'برای ارسال پیام بعدی کمی صبر کن.'; end if;
  insert into public.baladi_global_chat_messages(user_id, body, sticker_id) values (p_user_id, v_body, p_sticker_id) returning * into v_message;
  return jsonb_build_object('id', v_message.id, 'user_id', v_message.user_id, 'body', v_message.body, 'sticker_id', v_message.sticker_id, 'created_at', v_message.created_at);
end;
$function$;

create or replace function public.baladi_unlock_global_chat(p_user_id uuid)
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_profile public.baladi_game_profiles%rowtype;
  v_already_unlocked boolean;
begin
  select * into v_profile from public.baladi_game_profiles where user_id = p_user_id for update;
  if not found then raise exception 'پروفایل بازی پیدا نشد.'; end if;
  v_already_unlocked := v_profile.chat_unlocked_at is not null;
  update public.baladi_game_profiles set chat_unlocked_at = coalesce(chat_unlocked_at, now()), updated_at = now()
  where user_id = p_user_id returning * into v_profile;
  return jsonb_build_object('profile', to_jsonb(v_profile), 'already_unlocked', v_already_unlocked, 'cost', 0);
end;
$function$;