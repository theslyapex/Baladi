create or replace function public.baladi_matchmaking_join(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_opponent uuid; v_invite_id uuid; v_match jsonb; v_match_id uuid; v_display_name text;
begin
 perform pg_advisory_xact_lock(hashtext('baladi_matchmaking_global'));
 if not exists(select 1 from public.baladi_game_profiles where user_id=p_user_id) then raise exception 'پروفایل بازیکن پیدا نشد.'; end if;
 select id into v_match_id from public.baladi_duel_matches where status='active' and (player_one=p_user_id or player_two=p_user_id) order by started_at desc limit 1;
 if v_match_id is not null then return jsonb_build_object('status','matched','match_id',v_match_id); end if;
 update public.baladi_matchmaking_queue set status='expired',updated_at=now() where status='waiting' and updated_at<now()-interval '2 minutes';
 select q.user_id into v_opponent from public.baladi_matchmaking_queue q
 where q.status='waiting' and q.user_id<>p_user_id and q.updated_at>now()-interval '2 minutes'
 and not exists(select 1 from public.baladi_duel_matches m where m.status='active' and (m.player_one=q.user_id or m.player_two=q.user_id))
 order by q.created_at limit 1 for update skip locked;
 if v_opponent is null then
  insert into public.baladi_matchmaking_queue(user_id,status,opponent_id,invite_id,match_id,created_at,updated_at)
  values(p_user_id,'waiting',null,null,null,now(),now())
  on conflict(user_id) do update set status='waiting',opponent_id=null,invite_id=null,match_id=null,created_at=now(),updated_at=now();
  return jsonb_build_object('status','waiting');
 end if;
 insert into public.baladi_duel_invites(sender_id,recipient_id,expires_at) values(p_user_id,v_opponent,now()+interval '1 minute') returning id into v_invite_id;
 v_match:=public.baladi_accept_duel_invite(v_opponent,v_invite_id);
 v_match_id:=(v_match->>'match_id')::uuid;
 insert into public.baladi_matchmaking_queue(user_id,status,opponent_id,invite_id,match_id,created_at,updated_at)
 values(p_user_id,'matched',v_opponent,v_invite_id,v_match_id,now(),now())
 on conflict(user_id) do update set status='matched',opponent_id=excluded.opponent_id,invite_id=excluded.invite_id,match_id=excluded.match_id,updated_at=now();
 update public.baladi_matchmaking_queue set status='matched',opponent_id=p_user_id,invite_id=v_invite_id,match_id=v_match_id,updated_at=now() where user_id=v_opponent;
 select display_name into v_display_name from public.baladi_game_profiles where user_id=p_user_id;
 insert into public.account_notifications(user_id,source,source_id,event_key,title,body)
 values
 (p_user_id,'baladi_duel',v_match_id::text,'duel_matched:'||v_match_id::text,'حریف پیدا شد!','مسابقه دونفره با '||coalesce((select display_name from public.baladi_game_profiles where user_id=v_opponent),'بازیکن')||' آغاز شد.'),
 (v_opponent,'baladi_duel',v_match_id::text,'duel_matched:'||v_match_id::text,'حریف پیدا شد!','مسابقه دونفره با '||coalesce(v_display_name,'بازیکن')||' آغاز شد.')
 on conflict do nothing;
 return jsonb_build_object('status','matched','match_id',v_match_id,'opponent_id',v_opponent);
end;
$$;