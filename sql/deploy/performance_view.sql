-- Deploy fantasy_tf2:performance_view to pg

begin;

    create view performance_view as
    select performance.*
         , multiplier.multiplier as multiplier
         , value * multiplier.multiplier as score
      from performance
      join multiplier
        on multiplier.tournament = performance.tournament
       and multiplier.statistic = performance.statistic;

commit;
