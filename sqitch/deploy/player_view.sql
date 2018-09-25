-- Deploy fantasy_tf2:player_view to pg

begin;

    create view player_view as
         select *
           from player super;

commit;
