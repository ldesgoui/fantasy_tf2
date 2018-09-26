-- Deploy fantasy_tf2:contract_view to pg

begin;

    create materialized view contract_view as
        select contract.*
             , sum(score) as score
             , sum(score) / count(distinct map) as score_per_map
          from contract
     left join performance_view
            on performance_view.tournament = contract.tournament
           and performance_view.player = contract.player
     left join map on performance_view.map = map.url
     left join match on map.match = match.id
         where contract.time @> match.time
      group by contract.tournament
             , contract.manager
             , contract.player
             , contract.time
             , contract.purchase_price
             , contract.sale_price;

commit;
