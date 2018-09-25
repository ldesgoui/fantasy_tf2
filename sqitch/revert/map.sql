-- Revert fantasy_tf2:map from pg

begin;

    drop table map;

commit;
