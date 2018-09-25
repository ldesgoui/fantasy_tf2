-- Revert fantasy_tf2:performance from pg

begin;

    drop table performance;

commit;
