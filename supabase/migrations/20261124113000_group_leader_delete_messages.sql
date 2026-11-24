create or replace function public.baladi_delete_group_message(
  p_user_id uuid,
  p_group_id uuid,
  p_message_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_role text;
begin
  select role into v_role
  from public.baladi_group_members
  where group_id = p_group_id and user_id = p_user_id
  for update;

  if v_role is distinct from 'leader' then
    raise exception 'فقط رهبر گروه می‌تواند پیام‌ها را حذف کند.';
  end if;

  delete from public.baladi_group_messages
  where id = p_message_id and group_id = p_group_id;

  if not found then
    raise exception 'پیام گروه پیدا نشد.';
  end if;

  return jsonb_build_object('ok', true, 'deleted_message_id', p_message_id);
end;
$function$;

revoke all on function public.baladi_delete_group_message(uuid, uuid, bigint) from public, anon, authenticated;
grant execute on function public.baladi_delete_group_message(uuid, uuid, bigint) to service_role;