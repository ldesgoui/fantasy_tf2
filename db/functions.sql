-- functions.sql

create function my_team_standing()
    returns team_standing
    immutable
    language sql
    as $$
    select *
    from team_standing
    where manager = current_setting('request.jwt.claim.manager_id', true);
$$;

create function time_joined(contract)
    returns timestamp
    language sql
    as $$
        select lower($1.time);
$$;

create function time_left(contract)
    returns timestamp
    language sql
    as $$
        select upper($1.time);
$$;

create function time_joined(contract_value)
    returns timestamp
    language sql
    as $$
        select lower($1.time);
$$;

create function time_left(contract_value)
    returns timestamp
    language sql
    as $$
        select upper($1.time);
$$;

create function create_transaction(tnm text, new_roster text[])
    returns bool
    language plpgsql
    strict
    security definer
    as $$
        declare
            mgr text = current_setting('request.jwt.claim.manager_id', true);
        begin
            if not exists (
                    select steam_id
                      from manager
                     where steam_id = mgr
                ) then
                raise exception 'Manager does not exist';
            end if;

            update contract
               set time = tsrange(lower(time), now()::timestamp)
             where tournament = tnm
               and manager = mgr
               and upper(time) is null
               and not (player = any (new_roster));

            if exists (
                select 1
                  from team_transactions x
             left join tournament t on x.tournament = t.name
                 where x.tournament = tnm
                   and x.manager = mgr
                   and x.team_transactions > t.transactions
                ) then
                raise exception 'Exceeded amount of transactions available';
            end if;

            insert into contract
            select tnm as tournament
                 , mgr as manager
                 , unnest as player
                 , tsrange(now()::timestamp, null) as time
              from unnest(new_roster)
                on conflict do nothing;

            if exists (
                select 1
                  from team_cost x
             left join tournament t on x.tournament = t.name
                 where x.tournament = tnm
                   and x.manager = mgr
                   and x.team_cost > t.budget
                ) then
                raise exception 'Exceeded budget spending';
            end if;

            if exists (
                select 1
                  from team_composition
                 where tournament = tnm
                   and manager = mgr
                   and team_composition <> '{scout,scout,soldier,soldier,demoman,medic}'
                ) then
                raise exception 'Team composition requires 2 scouts, 2 soldiers, 1 demoman and 1 medic';
            end if;

            if exists (
                select 1
                  from team_overlap
                 where tournament = tnm
                   and manager = mgr
                   and count > 3
                ) then
                raise exception 'Fantasy team has a limit of 3 players from any team';
            end if;

            return 't';
        end;
$$;

create function import_logs(tournament text, id int, data jsonb)
    returns bool
    language plpgsql
    as $$
    declare
        player_id text;
        player jsonb;
        is_player_blue bool;
        frag_as_medic int;
        top_fragger text;
        top_damager text;
        top_kdr text;
        blue_score int;
        red_score int;
        blue_team_medic_death int;
        red_team_medic_death int;
    begin
        insert into match values
            ( id
            , tournament
            , to_timestamp((data->'info'->>'date')::int)
            , data->'info'->>'title'
            )
        on conflict do nothing;

        delete from match_performance
         where match = id;

        blue_score := data->'teams'->'Blue'->'score';
        red_score := data->'teams'->'Red'->'score';

        select key
          from jsonb_each(data->'players')
      order by value->'kills' desc
         limit 1
          into top_fragger;

        select key
          from jsonb_each(data->'players')
      order by value->'dmg' desc
         limit 1
          into top_damager;

        select key
          from jsonb_each(data->'players')
      order by value->'kpd' desc
         limit 1
          into top_kdr;

        select sum((value->>'medic')::int)
          from jsonb_each(data->'classkills')
         where data->'players'->key->>'team' = 'Red'
          into blue_team_medic_death;

        select sum((value->>'medic')::int)
          from jsonb_each(data->'classkills')
         where data->'players'->key->>'team' = 'Blue'
          into red_team_medic_death;

        for player_id in select * from jsonb_object_keys(data->'players') loop

            continue when not exists (
                select *
                  from player
                 where player.tournament = $1
                   and steam_id = player_id
            );

            player := data->'players'->player_id;
            is_player_blue := player->>'team' = 'Blue';

            select value->'kills'
              from jsonb_array_elements(player->'class_stats')
             where value->>'type' = 'medic'
              into frag_as_medic;

            if frag_as_medic is null then
                frag_as_medic := 0;
            end if;

            insert into match_performance values
                ( id
                , tournament
                , player_id
                , case when is_player_blue
                    then blue_score > red_score
                    else red_score > blue_score
                  end
                , case when is_player_blue
                    then blue_score
                    else red_score
                  end
                , (player->>'kills')::int
                , coalesce((data->'classkills'->player_id->>'medic')::int, 0)
                , frag_as_medic
                , (player->>'dapm')::int
                , (player->>'ubers')::int
                , (player->>'drops')::int
                , case when is_player_blue
                    then blue_team_medic_death
                    else red_team_medic_death
                  end
                , top_fragger = player_id
                , top_damager = player_id
                , top_kdr = player_id
                , (player->>'as')::int
                , (player->>'cpc')::int
                );

        end loop;

        return 't';
    end;
$$;
