-- Deploy fantasy_tf2:team_view to pg

begin;

    create materialized view private.team_view_helper as
        select team.tournament
             , team.manager
             , start_budget + sum(sale_price - purchase_price) filter (where upper(time) is not null) as total_budget
             , start_budget + sum(coalesce(sale_price, 0) - purchase_price) as remaining_budget
             , count(upper(time)) as transactions
             , sum(score) as score
          from team
     left join contract_view
            on contract_view.tournament = team.tournament
           and contract_view.manager = team.manager
      group by team.tournament, team.manager;

    create view team_view as
         select team.*
              , total_budget
              , remaining_budget
              , transactions
              , score
              , rank() over (partition by team.tournament order by score desc)
           from team
      left join private.team_view_helper
             on team_view_helper.tournament = team.tournament
            and team_view_helper.manager = team.manager;

commit;
