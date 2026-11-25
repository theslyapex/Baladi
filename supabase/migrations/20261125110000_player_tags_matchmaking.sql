create or replace function public.baladi_generate_player_tag()
returns text language plpgsql volatile set search_path = public, pg_temp as $$
declare v_tag text;
begin
  loop
    v_tag := 'BLD-' || lpad((floor(random() * 100000000)::bigint)::text, 8, '0');
    exit when not exists (select 1 from public.baladi_game_profiles where player_tag = v_tag);
  end loop;
  return v_tag;
end;
$$;
alter table public.baladi_game_profiles add column if not exists player_tag text;
update public.baladi_game_profiles set player_tag=public.baladi_generate_player_tag() where player_tag is null or btrim(player_tag)='';
alter table public.baladi_game_profiles alter column player_tag set default public.baladi_generate_player_tag();
alter table public.baladi_game_profiles alter column player_tag set not null;
create unique index if not exists baladi_game_profiles_player_tag_uidx on public.baladi_game_profiles(upper(player_tag));
create or replace function public.baladi_assign_player_tag()
returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
 if new.player_tag is null or btrim(new.player_tag)='' then new.player_tag:=public.baladi_generate_player_tag(); end if;
 return new;
end;
$$;
drop trigger if exists baladi_assign_player_tag_before_insert on public.baladi_game_profiles;
create trigger baladi_assign_player_tag_before_insert before insert on public.baladi_game_profiles for each row execute function public.baladi_assign_player_tag();

create table if not exists public.baladi_matchmaking_queue (
 user_id uuid primary key references public.baladi_game_profiles(user_id) on delete cascade,
 status text not null default 'waiting' check(status in ('waiting','matched','cancelled','expired')),
 opponent_id uuid references public.baladi_game_profiles(user_id) on delete set null,
 invite_id uuid references public.baladi_duel_invites(id) on delete set null,
 match_id uuid references public.baladi_duel_matches(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists baladi_matchmaking_queue_waiting_idx on public.baladi_matchmaking_queue(status,created_at) where status='waiting';

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
 order by q.created_at for update skip locked limit 1;
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
 return jsonb_build_object('status',v_row.status,'match_id',v_row.match_id,'opponent_id',v_row.opponent_id);
end;
$$;
create or replace function public.baladi_matchmaking_cancel(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 update public.baladi_matchmaking_queue set status='cancelled',updated_at=now() where user_id=p_user_id and status='waiting';
 return jsonb_build_object('ok',true);
end;
$$;
create or replace function public.baladi_send_duel_invite_by_tag(p_sender_id uuid,p_player_tag text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_target uuid; v_invite jsonb; v_invite_id uuid;
begin
 select user_id into v_target from public.baladi_game_profiles where upper(player_tag)=upper(btrim(p_player_tag)) limit 1;
 if v_target is null then raise exception 'بازیکنی با این تگ پیدا نشد.'; end if;
 if v_target=p_sender_id then raise exception 'نمی‌توانی خودت را به مسابقه دعوت کنی.'; end if;
 v_invite:=public.baladi_send_duel_invite(p_sender_id,v_target);
 v_invite_id:=(v_invite->>'invite_id')::uuid;
 insert into public.account_notifications(user_id,source,source_id,event_key,title,body)
 values(v_target,'baladi_duel_invites',v_invite_id::text,'duel_invite:'||v_invite_id::text,'دعوت به مسابقه دونفره',
 coalesce((select display_name from public.baladi_game_profiles where user_id=p_sender_id),'یک بازیکن')||' تو را به مسابقه دونفره دعوت کرده است.')
 on conflict do nothing;
 return v_invite||jsonb_build_object('recipient_id',v_target);
end;
$$;
grant execute on function public.baladi_matchmaking_join(uuid) to service_role;
grant execute on function public.baladi_matchmaking_status(uuid) to service_role;
grant execute on function public.baladi_matchmaking_cancel(uuid) to service_role;
grant execute on function public.baladi_send_duel_invite_by_tag(uuid,text) to service_role;