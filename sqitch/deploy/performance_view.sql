-- Deploy fantasy_tf2:performance_view to pg

begin;

    create view performance_view as
    select performance.*
         , coalesce(multiplier.multiplier, 0) as multiplier
         , value * coalesce(multiplier.multiplier, 0) as score
      from performance
 left join multiplier
        on multiplier.tournament = performance.tournament
       and multiplier.statistic = performance.statistic;


commit;
