-- Deploy fantasy_tf2:contract_view to pg

begin;

    -- matches played?
    -- maps played?

    create view contract_view as
         select *
           from contract super
              , lateral (
                 select sum(score) as score
                      , sum(score) / count(distinct map) as score_per_map
                   from performance_view
              left join map on performance_view.map = map.url
              left join match on map.match = match.id
                  where performance_view.tournament = super.tournament
                    and performance_view.player = super.player
                    and super.time @> match.time
                ) p;

commit;
