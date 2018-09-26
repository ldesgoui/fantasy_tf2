-- Deploy fantasy_tf2:player_view to pg

begin;

    create view player_view as
         select *
              , rank() over (partition by tournament, main_class order by score desc) as class_rank
              , rank() over (partition by tournament order by score desc)
           from player super
              , lateral (
                 select sum(score) as score
                      , sum(score) / count(distinct map) as score_per_map
                   from performance_view
                  where performance_view.tournament = super.tournament
                    and performance_view.player = super.player_id
                ) p;

commit;
