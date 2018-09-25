-- Deploy fantasy_tf2:team_view to pg

begin;

    create view team_view as
         select *
           from team super
              , lateral (
                 select super.start_budget + sum(case when upper(time) is not null then coalesce(sale_pr
ice, 0) - purchase_price else 0 end) as total_budget
                      , super.start_budget + sum(coalesce(sale_price, 0) - purchase_price) as remaining_
budget
                      , count(upper(time)) as transactions
                   from contract
                  where tournament = super.tournament
                    and manager = super.manager
                      ) b
                ;

commit;
