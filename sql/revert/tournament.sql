-- Revert fantasy_tf2:tournament from pg

begin;

    drop table tournament;

commit;
