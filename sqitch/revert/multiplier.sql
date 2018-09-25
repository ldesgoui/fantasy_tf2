-- Revert fantasy_tf2:tournament_score_multiplier from pg

begin;

    drop table multiplier;

commit;
