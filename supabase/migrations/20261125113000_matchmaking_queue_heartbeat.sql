create or replace function public.baladi_matchmaking_status(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.baladi_matchmaking_queue%rowtype;
begin
 select * into v_row from public.baladi_matchmaking_queue where user_id=p_user_id;
 if not found then return jsonb_build_object('status','idle'); end if;
 if v_row.status='waiting' and v_row.updated_at<now()-interval '2 minutes' then
  update public.baladi_matchmaking_queue set status='expired',updated_at=now() where user_id=p_user_id;
  return jsonb_build_object('status','expired');
 end if;
 if v_row.status='waiting' then update public.baladi_matchmaking_queue set updated_at=now() where user_id=p_user_id; end if;
 return jsonb_build_object('status',v_row.status,'match_id',v_row.match_id,'opponent_id',v_row.opponent_id);
end;
$$;