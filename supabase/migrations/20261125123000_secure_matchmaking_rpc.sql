revoke all on function public.baladi_matchmaking_join(uuid) from public, anon, authenticated;
revoke all on function public.baladi_matchmaking_status(uuid) from public, anon, authenticated;
revoke all on function public.baladi_matchmaking_cancel(uuid) from public, anon, authenticated;
revoke all on function public.baladi_send_duel_invite_by_tag(uuid,text) from public, anon, authenticated;
grant execute on function public.baladi_matchmaking_join(uuid) to service_role;
grant execute on function public.baladi_matchmaking_status(uuid) to service_role;
grant execute on function public.baladi_matchmaking_cancel(uuid) to service_role;
grant execute on function public.baladi_send_duel_invite_by_tag(uuid,text) to service_role;