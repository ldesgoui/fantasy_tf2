-- Revert fantasy_tf2:manager from pg

begin;

    drop table manager;

commit;
