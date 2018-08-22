-- view.sql

create view match_performance_score as
    select *
         , game_win::int * 3
         + round_win * 3
         + frag
         + medic_frag
         + frag_as_medic * 2
         + dpm / 25
         + ubercharge * 2
         + ubercharge_dropped * -3
         + team_medic_death / -5
         + top_frag::int * 2
         + top_damage::int * 2
         + top_kdr::int * 2
         + airshot / 5
         + capture as total_score
      from match_performance;

create view player_total_score as
    select p.*
         , count(1) as matches_played
         , sum(m.total_score) as total_score
         , sum(m.total_score) / count(1) as efficiency
      from player p
 left join match_performance_score m on (m.tournament, m.player) = (p.tournament, p.steam_id)
  group by (p.tournament, p.steam_id);

create view player_standing as
    select *
         , dense_rank() over (order by total_score desc) as rank
         , dense_rank() over (order by efficiency desc) as efficiency_rank
      from player_total_score;

create view active_contract as
     select c.tournament
          , c.manager
          , lower(c.time) as time_joined
          , p.steam_id
          , p.name
          , p.team
          , p.main_class
          , p.price
       from contract c
  left join player p on (c.tournament, c.player) = (p.tournament, p.steam_id)
      where upper(time) is null;

create view contract_value as
    select c.*
         , count(1) as matches_played
         , sum(p.total_score) as total_score
         , sum(p.total_score) / count(1) as efficiency
      from contract c
 left join match_performance_score p on (c.tournament, c.player) = (p.tournament, p.player)
 left join match m on p.match = m.id
     where c.time @> m.time
  group by (c.tournament, c.manager, c.player, c.time);

create view team_score as
    select tournament
         , manager
         , sum(total_score) as total_score
      from (
         select tournament
              , manager
              , total_score from contract_value
      union all
         select tournament
              , manager
              , 0 as total_score
           from fantasy_team
      ) f
  group by (tournament, manager);

create view team_standing as
    select *
         , dense_rank() over (order by total_score desc) as rank
      from team_score;

create view team_cost as
     select tournament
          , manager
          , sum(price) as team_cost
       from active_contract
   group by (tournament, manager);

create view team_transactions as
    select tournament
         , manager
         , count(1) as team_transactions
      from contract
     where upper(time) is not null
  group by (tournament, manager);

create view team_overlap as
    select tournament
         , manager
         , team
         , count(1)
      from active_contract
  group by (tournament, manager, team);

create view team_composition as
    select tournament
         , manager
         , array_agg(main_class) as team_composition
      from (select * from active_contract order by main_class) f
  group by (tournament, manager);

