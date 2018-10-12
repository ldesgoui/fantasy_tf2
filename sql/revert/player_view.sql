-- Revert fantasy_tf2:player_view from pg

begin;

    drop view player_view;

commit;
