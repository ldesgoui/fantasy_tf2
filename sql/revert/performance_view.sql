-- Revert fantasy_tf2:performance_view from pg

begin;

    drop view performance_view;

commit;
