-- Revert fantasy_tf2:contract from pg

begin;

    drop table contract;

commit;
