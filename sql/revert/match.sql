-- Revert fantasy_tf2:match from pg

begin;

    drop table match;

commit;
