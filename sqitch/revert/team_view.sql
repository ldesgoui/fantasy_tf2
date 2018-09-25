-- Revert fantasy_tf2:team_view from pg

begin;

    drop view team_view;

commit;
