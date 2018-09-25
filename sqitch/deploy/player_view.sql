-- Deploy fantasy_tf2:player_view to pg

begin;

    -- rank
    -- dense_rank
    -- * score
    -- * score_per_map
    -- * main_class
    -- matches played ? maps played ?

    create view player_view as
         select *
           from player super
              , lateral (
                 select sum(score) as score
                      , sum(score) / count(distinct map) as score_per_map
                   from performance_view
                  where performance_view.tournament = super.tournament
                    and performance_view.player = super.player_id
                ) p;

commit;
