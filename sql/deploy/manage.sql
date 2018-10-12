-- Deploy fantasy_tf2:manage to pg

begin;

    create function manage
                  ( tournament_slug text
                  , new_team_name text
                  , new_roster text[]
                  )
            returns void
           language plpgsql
             strict
           security definer
                 as $$
        declare
            manager_id text = current_setting('request.jwt.claim.manager_id', true);
        begin
            if not exists (select steam_id from manager where steam_id = manager_id) then
                raise exception 'Manager does not exist';
            end if;

            if exists (
                select 1
                  from tournament
                 where slug = tournament_slug
                   and end_time < now()
                ) then
                raise exception 'Tournament is over, you may not change your roster anymore';
            end if;

            insert into team
            select tournament_slug as tournament
                 , manager_id as manager
                 , new_team_name as name
                 , tournament.start_budget
              from tournament
             where tournament.slug = tournament_slug
                on conflict do nothing;

            update contract
               set time = tsrange(lower(time), now()::timestamp)
                 , sale_price = p.price
              from player p
             where p.tournament = tournament_slug
               and p.player_id = player
               and tournament = tournament_slug
               and manager = manager_id
               and upper(time) is null
               and not (player = any (new_roster));

            insert into contract
            select tournament_slug as tournament
                 , manager_id as manager
                 , unnest as player
                 , tsrange(now()::timestamp, null) as time
                 , player.price as purchase_price
              from unnest(new_roster)
         left join player on player.player_id = unnest
                on conflict do nothing;

            if exists (
                select 1
                  from team_view x
             left join tournament t on t.slug = x.tournament
                 where x.tournament = tournament_slug
                   and x.manager = manager_id
                   and x.transactions > t.transactions
                ) then
                raise exception 'Exceeded amount of transactions available';
            end if;

            if exists (
                select 1
                  from team_view
                 where tournament = tournament_slug
                   and manager = manager_id
                   and remaining_budget < 0
                ) then
                raise exception 'Exceeded budget spending';
            end if;

            if exists (
                select 1
                  from contract
             left join player
                    on player.tournament = contract.tournament
                   and player.player_id = contract.player
                 where contract.tournament = tournament_slug
                   and contract.manager = manager_id
                   and upper(time) is null
                having array_agg(main_class order by main_class)
                   <> '{scout,scout,soldier,soldier,demoman,medic}'
                ) then
                raise exception 'Team composition requires 2 scouts, 2 soldiers, 1 demoman and 1 medic';
            end if;

            if exists (
                select 1
                  from contract
             left join player on player.player_id = contract.player
                 where tournament = tournament_slug
                   and manager = manager_id
                   and upper(time) is not null
              group by (tournament, manager, player.team)
                having count() > 2
                ) then
                raise exception 'Fantasy team has a limit of 2 players from any team';
            end if;
        end;
    $$;

commit;
