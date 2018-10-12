-- Revert fantasy_tf2:team from pg

begin;

    drop table team;

commit;
