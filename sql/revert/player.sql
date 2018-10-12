-- Revert fantasy_tf2:player from pg

begin;

    drop table player;

commit;
