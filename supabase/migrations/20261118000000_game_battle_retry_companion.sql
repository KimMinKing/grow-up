-- Preserve a first-clear companion in the resolved battle record so a lost
-- Edge Function response can be retried without hiding the awarded creature.
alter table public.game_battle_attempts
  add column companion_species_id text
    check (companion_species_id in
      ('pine_fox', 'wave_otter', 'star_crow', 'pebble_newt'));

create function public.record_game_battle_companion()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.source = 'battle' then
    update public.game_battle_attempts as attempt
      set companion_species_id = new.species_id
      where attempt.user_id = new.user_id
        and attempt.status = 'pending'
        and exists (
          select 1 from public.game_verified_battles as verified
            where verified.battle_ref = attempt.request_id
              and verified.user_id = new.user_id
              and verified.stage_id = attempt.stage_id
              and verified.won
        );
  end if;
  return new;
end;
$$;

revoke all on function public.record_game_battle_companion()
  from public, anon, authenticated;

create trigger game_record_battle_companion
  after insert on public.game_creature_instances
  for each row execute function public.record_game_battle_companion();
