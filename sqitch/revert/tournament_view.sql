-- Revert fantasy_tf2:tournament_view from pg

begin;

    drop view tournament_view;

commit;
