-- Allow the chapter milestone event emitted by baladi_complete_level.
-- Without this event type, level 20 completion rolls back after the profile update.
alter table public.baladi_game_events
  drop constraint if exists baladi_game_events_event_type_check;

alter table public.baladi_game_events
  add constraint baladi_game_events_event_type_check
  check (event_type = any (array[
    'level_completed',
    'hint_used',
    'word_found',
    'bonus_word_found',
    'daily_streak_reward',
    'hint_clue_used',
    'monthly_leaderboard_reward',
    'group_contribution',
    'group_daily_reward',
    'chapter_diamond_reward'
  ]::text[]));
