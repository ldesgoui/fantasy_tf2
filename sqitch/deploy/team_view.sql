-- Deploy fantasy_tf2:team_view to pg

begin;

    -- rank
    -- dense_rank
    -- * score
    -- * score_per_map

    create view team_view as
         select *
           from team super
              , lateral (
                 select super.start_budget + sum(sale_price - purchase_price) filter (where upper(time) is not null) as total_budget
                      , super.start_budget + sum(coalesce(sale_price, 0) - purchase_price) as remaining_budget
                      , count(upper(time)) as transactions
                      , sum(score) as score
                   from contract_view
                  where tournament = super.tournament
                    and manager = super.manager
                      ) c;

commit;
