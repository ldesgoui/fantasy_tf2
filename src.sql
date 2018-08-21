drop schema fantasy_tf2 cascade;
drop role anonymous;
drop role manager;
drop role admin;

begin;

    create schema fantasy_tf2;
    set search_path to fantasy_tf2;

    create extension if not exists btree_gist;

    create type class as enum
        ( 'scout'
        , 'soldier'
        , 'pyro'
        , 'demoman'
        , 'heavy'
        , 'engineer'
        , 'medic'
        , 'sniper'
        , 'spy'
        );

    create table tournament
        ( slug                  text primary key
        , name                  text not null
        , budget                int not null
        , transactions          int not null
        );

    create table team
        ( tournament            text references tournament
        , name                  text
        , primary key (tournament, name)
        );

    create table player
        ( tournament            text references tournament
        , steam_id              text
        , name                  text not null
        , team                  text not null
        , main_class            class not null
        , price                 int not null
        , primary key (tournament, steam_id)
        , foreign key (tournament, team) references team
        );

    create table match
        ( id                    int primary key
        , tournament            text not null references tournament
        , time                  timestamp not null
        , name                  text not null
        );

    create table match_performance
        ( match                 int references match
        , tournament            text not null references tournament
        , player                text not null
        , game_win              bool not null
        , round_win             int not null
        , frag                  int not null
        , medic_frag            int not null
        , frag_as_medic         int not null
        , dpm                   float not null
        , ubercharge            int not null
        , ubercharge_dropped    int not null
        , team_medic_death      int not null
        , top_frag              bool not null
        , top_damage            bool not null
        , top_kdr               bool not null
        , airshot               int not null
        , capture               int not null
        , foreign key (tournament, player) references player
        );

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

    create table manager
        ( steam_id              text primary key
        , name                  text not null
        );

    create table fantasy_team
        ( tournament            text references tournament
        , manager               text references manager
        , name                  text not null
        , primary key (tournament, manager)
        );

    create table contract
        ( tournament            text not null references tournament
        , manager               text not null references manager
        , player                text not null
        , time                  tsrange not null
        , foreign key (tournament, manager) references fantasy_team
        , foreign key (tournament, player) references player
        , exclude using gist
            ( tournament with =
            , manager with =
            , player with =
            , time with &&
            )
        );

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

                if array_length(new_roster, 1) <> 6 then
                    raise exception 'New roster must be 6 players';
                end if;

                update contract
                   set time = tsrange(lower(time), now()::timestamp + interval '1 hour')
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

    create role anonymous nologin;
    create role manager nologin;
    create role admin nologin;

    grant anonymous to postgres;
    grant manager to postgres;
    grant admin to postgres;

commit;
begin;

    select set_config('request.jwt.claim.manager_id', '0', false);

    insert into tournament values
        ( 'i63'
        , 'Insomnia 63 by Essentials.TF'
        , 130000
        , 8
        );

    insert into team values
        ( 'i63'
        , 'Se7en'
        ),
        ( 'i63'
        , 'froyotech'
        );

    insert into player values
        ( 'i63'
        , '[U:1:111776267]'
        , 'kaidus'
        , 'Se7en'
        , 'demoman'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:118758944]'
        , 'Thalash'
        , 'Se7en'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:167517704]'
        , 'Thaigrr'
        , 'Se7en'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:172044269]'
        , 'Adysky'
        , 'Se7en'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:172534925]'
        , 'stark'
        , 'Se7en'
        , 'medic'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:178869439]'
        , 'AMS'
        , 'Se7en'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:204729823]'
        , 'shade'
        , 'froyotech'
        , 'medic'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:247875068]'
        , 'b4nny'
        , 'froyotech'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:51723097]'
        , 'blaze'
        , 'froyotech'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:59977210]'
        , 'habib'
        , 'froyotech'
        , 'demoman'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:81145222]'
        , 'yomps'
        , 'froyotech'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:95820688]'
        , 'arekk'
        , 'froyotech'
        , 'scout'
        , '1000'
        );

    insert into manager values
        ( '0'
        , 'twiikuu'
        ),
        ( '1'
        , 'fjksjkf'
        );

    insert into fantasy_team values
        ( 'i63'
        , '0'
        , 'WARHURYEAH IS FOREVER'
        ),
        ( 'i63'
        , '1'
        , 'gah'
        );

    select create_transaction('i63', ARRAY[
        '[U:1:111776267]',
        '[U:1:118758944]',
        '[U:1:167517704]',
        '[U:1:51723097]',
        '[U:1:81145222]',
        '[U:1:204729823]'
        ]);
    select create_transaction('i63', ARRAY[
        '[U:1:172044269]',
        '[U:1:172534925]',
        '[U:1:178869439]',
        '[U:1:247875068]',
        '[U:1:59977210]',
        '[U:1:95820688]'
    ]);








































    select import_logs('i63', '1983350', '{"version": 3, "teams": {"Red": {"score": 2, "kills": 108, "deaths": 0, "dmg": 35107, "charges": 12, "drops": 1, "firstcaps": 3, "caps": 19}, "Blue": {"score": 1, "kills": 94, "deaths": 0, "dmg": 32290, "charges": 8, "drops": 1, "firstcaps": 1, "caps": 17}}, "length": 2018, "players": {"[U:1:111776267]": {"team": "Blue", "class_stats": [{"type": "scout", "kills": 19, "assists": 10, "deaths": 18, "dmg": 4387, "weapon": {"scattergun": {"kills": 15, "dmg": 4147, "avg_dmg": 22.661202185792348, "shots": 0, "hits": 0}, "maxgun": {"kills": 2, "dmg": 205, "avg_dmg": 17.083333333333332, "shots": 0, "hits": 0}, "world": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}, "scout_sword": {"kills": 1, "dmg": 35, "avg_dmg": 35, "shots": 0, "hits": 0}}, "total_time": 1743}, {"type": "heavyweapons", "kills": 1, "assists": 3, "deaths": 1, "dmg": 549, "weapon": {"minigun": {"kills": 1, "dmg": 549, "avg_dmg": 12.2, "shots": 0, "hits": 0}}, "total_time": 174}], "kills": 20, "deaths": 19, "assists": 13, "suicides": 0, "kapd": "1.7", "kpd": "1.1", "dmg": 4936, "dmg_real": 2149, "dt": 6041, "dt_real": 535, "hr": 4005, "lks": 5, "as": 0, "dapd": 259, "dapm": 146, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 27, "medkits_hp": 636, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 3250, "cpc": 8, "ic": 0}, "[U:1:172534925]": {"team": "Blue", "class_stats": [{"type": "soldier", "kills": 11, "assists": 7, "deaths": 21, "dmg": 7142, "weapon": {"tf_projectile_rocket": {"kills": 6, "dmg": 7012, "avg_dmg": 60.97391304347826, "shots": 0, "hits": 0}, "unique_pickaxe_escape": {"kills": 1, "dmg": 130, "avg_dmg": 65, "shots": 0, "hits": 0}, "world": {"kills": 4, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 2018}], "kills": 11, "deaths": 21, "assists": 7, "suicides": 0, "kapd": "0.9", "kpd": "0.5", "dmg": 7142, "dmg_real": 391, "dt": 6765, "dt_real": 855, "hr": 2358, "lks": 2, "as": 4, "dapd": 340, "dapm": 212, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 79, "medkits_hp": 2905, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 1112, "cpc": 6, "ic": 0}, "[U:1:204729823]": {"team": "Red", "class_stats": [{"type": "scout", "kills": 23, "assists": 4, "deaths": 15, "dmg": 4158, "weapon": {"scattergun": {"kills": 20, "dmg": 4125, "avg_dmg": 30.555555555555557, "shots": 0, "hits": 0}, "the_capper": {"kills": 1, "dmg": 33, "avg_dmg": 16.5, "shots": 0, "hits": 0}, "world": {"kills": 2, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1663}, {"type": "sniper", "kills": 2, "assists": 0, "deaths": 1, "dmg": 268, "weapon": {"sniperrifle": {"kills": 1, "dmg": 257, "avg_dmg": 85.66666666666667, "shots": 0, "hits": 0}, "smg": {"kills": 1, "dmg": 11, "avg_dmg": 11, "shots": 0, "hits": 0}}, "total_time": 184}, {"type": "pyro", "kills": 0, "assists": 1, "deaths": 2, "dmg": 308, "weapon": {"flamethrower": {"kills": 0, "dmg": 186, "avg_dmg": 6.642857142857143, "shots": 0, "hits": 0}, "deflect_rocket": {"kills": 0, "dmg": 122, "avg_dmg": 122, "shots": 0, "hits": 0}}, "total_time": 138}, {"type": "heavyweapons", "kills": 2, "assists": 1, "deaths": 0, "dmg": 243, "weapon": {"minigun": {"kills": 2, "dmg": 243, "avg_dmg": 12.15, "shots": 0, "hits": 0}}, "total_time": 33}], "kills": 27, "deaths": 18, "assists": 6, "suicides": 0, "kapd": "1.8", "kpd": "1.5", "dmg": 4977, "dmg_real": 1586, "dt": 4588, "dt_real": 777, "hr": 2905, "lks": 6, "as": 0, "dapd": 276, "dapm": 147, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 17, "medkits_hp": 400, "backstabs": 0, "headshots": 1, "headshots_hit": 1, "sentries": 0, "heal": 3216, "cpc": 9, "ic": 0}, "[U:1:51723097]": {"team": "Blue", "class_stats": [{"type": "soldier", "kills": 12, "assists": 2, "deaths": 18, "dmg": 5841, "weapon": {"tf_projectile_rocket": {"kills": 2, "dmg": 1395, "avg_dmg": 43.59375, "shots": 0, "hits": 0}, "shotgun_soldier": {"kills": 0, "dmg": 40, "avg_dmg": 13.333333333333334, "shots": 0, "hits": 0}, "quake_rl": {"kills": 9, "dmg": 4398, "avg_dmg": 63.73913043478261, "shots": 0, "hits": 0}, "world": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}, "flamethrower": {"kills": 0, "dmg": 8, "avg_dmg": 4, "shots": 0, "hits": 0}}, "total_time": 1926}, {"type": "pyro", "kills": 1, "assists": 0, "deaths": 2, "dmg": 492, "weapon": {"flamethrower": {"kills": 1, "dmg": 307, "avg_dmg": 6.14, "shots": 0, "hits": 0}, "detonator": {"kills": 0, "dmg": 185, "avg_dmg": 5.138888888888889, "shots": 0, "hits": 0}}, "total_time": 89}], "kills": 13, "deaths": 20, "assists": 2, "suicides": 0, "kapd": "0.8", "kpd": "0.7", "dmg": 6333, "dmg_real": 796, "dt": 8021, "dt_real": 707, "hr": 6856, "lks": 4, "as": 4, "dapd": 316, "dapm": 188, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 30, "medkits_hp": 1097, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 2632, "cpc": 6, "ic": 0}, "[U:1:118758944]": {"team": "Red", "class_stats": [{"type": "demoman", "kills": 23, "assists": 8, "deaths": 13, "dmg": 9087, "weapon": {"tf_projectile_pipe_remote": {"kills": 10, "dmg": 5993, "avg_dmg": 63.084210526315786, "shots": 0, "hits": 0}, "tf_projectile_pipe": {"kills": 13, "dmg": 3094, "avg_dmg": 81.42105263157895, "shots": 0, "hits": 0}}, "total_time": 2018}], "kills": 23, "deaths": 13, "assists": 8, "suicides": 0, "kapd": "2.4", "kpd": "1.8", "dmg": 9087, "dmg_real": 1056, "dt": 6064, "dt_real": 1987, "hr": 7586, "lks": 6, "as": 1, "dapd": 699, "dapm": 270, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 30, "medkits_hp": 1076, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 6022, "cpc": 4, "ic": 0}, "[U:1:95820688]": {"team": "Blue", "class_stats": [{"type": "scout", "kills": 19, "assists": 6, "deaths": 9, "dmg": 4337, "weapon": {"scattergun": {"kills": 16, "dmg": 4125, "avg_dmg": 34.95762711864407, "shots": 0, "hits": 0}, "flamethrower": {"kills": 0, "dmg": 20, "avg_dmg": 4, "shots": 0, "hits": 0}, "boston_basher": {"kills": 1, "dmg": 35, "avg_dmg": 35, "shots": 0, "hits": 0}, "the_capper": {"kills": 2, "dmg": 157, "avg_dmg": 9.8125, "shots": 0, "hits": 0}}, "total_time": 1583}, {"type": "sniper", "kills": 9, "assists": 1, "deaths": 4, "dmg": 2698, "weapon": {"sniperrifle": {"kills": 9, "dmg": 2678, "avg_dmg": 167.375, "shots": 0, "hits": 0}, "smg": {"kills": 0, "dmg": 20, "avg_dmg": 10, "shots": 0, "hits": 0}}, "total_time": 370}, {"type": "pyro", "kills": 0, "assists": 0, "deaths": 2, "dmg": 214, "weapon": {"flamethrower": {"kills": 0, "dmg": 214, "avg_dmg": 5.944444444444445, "shots": 0, "hits": 0}}, "total_time": 65}], "kills": 28, "deaths": 15, "assists": 7, "suicides": 0, "kapd": "2.3", "kpd": "1.9", "dmg": 7249, "dmg_real": 2798, "dt": 4698, "dt_real": 679, "hr": 5381, "lks": 5, "as": 0, "dapd": 483, "dapm": 215, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 18, "medkits_hp": 389, "backstabs": 0, "headshots": 6, "headshots_hit": 7, "sentries": 0, "heal": 4492, "cpc": 11, "ic": 0}, "[U:1:167517704]": {"team": "Blue", "class_stats": [{"type": "medic", "kills": 0, "assists": 9, "deaths": 16, "dmg": 400, "weapon": {"crusaders_crossbow": {"kills": 0, "dmg": 400, "avg_dmg": 66.66666666666667, "shots": 0, "hits": 0}}, "total_time": 2018}], "kills": 0, "deaths": 16, "assists": 9, "suicides": 0, "kapd": "0.6", "kpd": "0.0", "dmg": 400, "dmg_real": 359, "dt": 4246, "dt_real": 715, "hr": 0, "lks": 0, "as": 0, "dapd": 25, "dapm": 11, "ubers": 8, "ubertypes": {"medigun": 7, "kritzkrieg": 1}, "drops": 1, "medkits": 5, "medkits_hp": 132, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 23625, "cpc": 4, "ic": 0, "medicstats": {"advantages_lost": 0, "biggest_advantage_lost": 0, "deaths_within_20s_after_uber": 3, "deaths_with_95_99_uber": 0, "avg_time_before_healing": 8.489473684210527, "avg_time_to_build": 72.75, "avg_time_before_using": 54, "avg_uber_length": 6.957142857142857}}, "[U:1:178869439]": {"team": "Blue", "class_stats": [{"type": "demoman", "kills": 22, "assists": 7, "deaths": 17, "dmg": 6230, "weapon": {"tf_projectile_pipe_remote": {"kills": 18, "dmg": 4944, "avg_dmg": 66.8108108108108, "shots": 0, "hits": 0}, "tf_projectile_pipe": {"kills": 2, "dmg": 1286, "avg_dmg": 71.44444444444444, "shots": 0, "hits": 0}, "world": {"kills": 2, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 2018}], "kills": 22, "deaths": 17, "assists": 7, "suicides": 0, "kapd": "1.7", "kpd": "1.3", "dmg": 6230, "dmg_real": 864, "dt": 5336, "dt_real": 2675, "hr": 5025, "lks": 5, "as": 3, "dapd": 366, "dapm": 185, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 27, "medkits_hp": 1011, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 1345, "cpc": 4, "ic": 0}, "[U:1:59977210]": {"team": "Red", "class_stats": [{"type": "soldier", "kills": 9, "assists": 4, "deaths": 20, "dmg": 5404, "weapon": {"tf_projectile_rocket": {"kills": 8, "dmg": 5404, "avg_dmg": 58.73913043478261, "shots": 0, "hits": 0}, "world": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 2007}], "kills": 9, "deaths": 20, "assists": 4, "suicides": 0, "kapd": "0.7", "kpd": "0.5", "dmg": 5404, "dmg_real": 375, "dt": 6347, "dt_real": 2763, "hr": 3268, "lks": 3, "as": 2, "dapd": 270, "dapm": 160, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 45, "medkits_hp": 1615, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 9, "ic": 0}, "[U:1:81145222]": {"team": "Red", "class_stats": [{"type": "scout", "kills": 21, "assists": 17, "deaths": 13, "dmg": 6345, "weapon": {"scattergun": {"kills": 15, "dmg": 5991, "avg_dmg": 26.3920704845815, "shots": 0, "hits": 0}, "pistol_scout": {"kills": 3, "dmg": 354, "avg_dmg": 16.857142857142858, "shots": 0, "hits": 0}, "world": {"kills": 3, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1767}, {"type": "engineer", "kills": 2, "assists": 0, "deaths": 1, "dmg": 387, "weapon": {"obj_sentrygun": {"kills": 1, "dmg": 136, "avg_dmg": 17, "shots": 0, "hits": 0}, "shotgun_primary": {"kills": 1, "dmg": 251, "avg_dmg": 31.375, "shots": 0, "hits": 0}}, "total_time": 190}, {"type": "pyro", "kills": 1, "assists": 1, "deaths": 1, "dmg": 277, "weapon": {"scorch_shot": {"kills": 0, "dmg": 186, "avg_dmg": 7.153846153846154, "shots": 0, "hits": 0}, "flamethrower": {"kills": 1, "dmg": 91, "avg_dmg": 6.5, "shots": 0, "hits": 0}}, "total_time": 57}], "kills": 24, "deaths": 15, "assists": 18, "suicides": 0, "kapd": "2.8", "kpd": "1.6", "dmg": 7009, "dmg_real": 1879, "dt": 4675, "dt_real": 606, "hr": 5381, "lks": 6, "as": 0, "dapd": 467, "dapm": 208, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 15, "medkits_hp": 276, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 12, "ic": 0}, "[U:1:247875068]": {"team": "Red", "class_stats": [{"type": "medic", "kills": 2, "assists": 14, "deaths": 8, "dmg": 460, "weapon": {"crusaders_crossbow": {"kills": 1, "dmg": 330, "avg_dmg": 55, "shots": 0, "hits": 0}, "ubersaw": {"kills": 1, "dmg": 130, "avg_dmg": 65, "shots": 0, "hits": 0}}, "total_time": 2018}], "kills": 2, "deaths": 8, "assists": 14, "suicides": 0, "kapd": "2.0", "kpd": "0.3", "dmg": 460, "dmg_real": 66, "dt": 2886, "dt_real": 205, "hr": 0, "lks": 1, "as": 0, "dapd": 57, "dapm": 13, "ubers": 12, "ubertypes": {"medigun": 12}, "drops": 1, "medkits": 3, "medkits_hp": 90, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 25257, "cpc": 3, "ic": 0, "medicstats": {"deaths_with_95_99_uber": 0, "advantages_lost": 0, "biggest_advantage_lost": 0, "deaths_within_20s_after_uber": 2, "avg_time_before_healing": 8.608333333333334, "avg_time_to_build": 85.23076923076923, "avg_time_before_using": 36.083333333333336, "avg_uber_length": 7.18}}, "[U:1:172044269]": {"team": "Red", "class_stats": [{"type": "soldier", "kills": 23, "assists": 4, "deaths": 20, "dmg": 8170, "weapon": {"quake_rl": {"kills": 23, "dmg": 8170, "avg_dmg": 63.828125, "shots": 0, "hits": 0}}, "total_time": 2015}], "kills": 23, "deaths": 20, "assists": 4, "suicides": 0, "kapd": "1.4", "kpd": "1.1", "dmg": 8170, "dmg_real": 1204, "dt": 7730, "dt_real": 1019, "hr": 5515, "lks": 3, "as": 4, "dapd": 408, "dapm": 242, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 32, "medkits_hp": 1241, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 0, "ic": 0}}, "names": {"[U:1:111776267]": "wanderlust_", "[U:1:172534925]": "_Sen", "[U:1:204729823]": "KoOoOOdEEeEeeY", "[U:1:51723097]": "sage LF demo 6s", "[U:1:118758944]": "Lava", "[U:1:95820688]": "Dominant", "[U:1:167517704]": "Beelthazus", "[U:1:178869439]": "herpestim", "[U:1:59977210]": "twiikuu | tf2.gg tf2pl.com", "[U:1:81145222]": "ash", "[U:1:247875068]": "Zaid", "[U:1:172044269]": "eldoccc"}, "rounds": [{"start_time": 1521142844, "winner": "Red", "team": {"Blue": {"score": 0, "kills": 9, "dmg": 3495, "ubers": 1}, "Red": {"score": 1, "kills": 17, "dmg": 5506, "ubers": 2}}, "events": [{"type": "medic_death", "time": 38, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:111776267]"}, {"type": "pointcap", "time": 50, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 65, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 84, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "medic_death", "time": 94, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:59977210]"}, {"type": "pointcap", "time": 129, "team": "Red", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 135, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 141, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:59977210]"}, {"type": "pointcap", "time": 152, "team": "Red", "point": 3}, {"type": "pointcap", "time": 165, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 210, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "pointcap", "time": 220, "team": "Red", "point": 1}, {"type": "round_win", "time": 220, "team": "Red"}], "players": {"[U:1:118758944]": {"team": "Red", "kills": 4, "dmg": 1636}, "[U:1:178869439]": {"team": "Blue", "kills": 2, "dmg": 635}, "[U:1:204729823]": {"team": "Red", "kills": 5, "dmg": 1047}, "[U:1:95820688]": {"team": "Blue", "kills": 2, "dmg": 654}, "[U:1:111776267]": {"team": "Blue", "kills": 3, "dmg": 382}, "[U:1:81145222]": {"team": "Red", "kills": 2, "dmg": 904}, "[U:1:51723097]": {"team": "Blue", "kills": 0, "dmg": 739}, "[U:1:59977210]": {"team": "Red", "kills": 3, "dmg": 765}, "[U:1:172534925]": {"team": "Blue", "kills": 2, "dmg": 1085}, "[U:1:172044269]": {"team": "Red", "kills": 3, "dmg": 1106}, "[U:1:247875068]": {"team": "Red", "kills": 0, "dmg": 48}, "[U:1:167517704]": {"team": "Blue", "kills": 0, "dmg": 0}}, "firstcap": "Blue", "length": 220}, {"start_time": 1521143074, "winner": "Red", "team": {"Blue": {"score": 0, "kills": 25, "dmg": 8333, "ubers": 1}, "Red": {"score": 2, "kills": 32, "dmg": 9344, "ubers": 3}}, "events": [{"type": "medic_death", "time": 258, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "pointcap", "time": 265, "team": "Red", "point": 3}, {"type": "pointcap", "time": 280, "team": "Red", "point": 2}, {"type": "pointcap", "time": 324, "team": "Blue", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 324, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 348, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:172044269]"}, {"type": "pointcap", "time": 373, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 414, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 432, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:95820688]"}, {"type": "pointcap", "time": 451, "team": "Blue", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 465, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "pointcap", "time": 483, "team": "Blue", "point": 3}, {"type": "medic_death", "time": 503, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:81145222]"}, {"type": "pointcap", "time": 530, "team": "Red", "point": 3}, {"type": "drop", "time": 571, "team": "Red", "steamid": "[U:1:247875068]"}, {"type": "medic_death", "time": 571, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:95820688]"}, {"type": "medic_death", "time": 583, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "pointcap", "time": 624, "team": "Blue", "point": 3}, {"type": "medic_death", "time": 655, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "pointcap", "time": 666, "team": "Red", "point": 3}, {"type": "pointcap", "time": 677, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 693, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 698, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:172044269]"}, {"type": "pointcap", "time": 698, "team": "Red", "point": 1}, {"type": "round_win", "time": 698, "team": "Red"}], "players": {"[U:1:178869439]": {"team": "Blue", "kills": 7, "dmg": 1983}, "[U:1:111776267]": {"team": "Blue", "kills": 3, "dmg": 1010}, "[U:1:81145222]": {"team": "Red", "kills": 8, "dmg": 1858}, "[U:1:204729823]": {"team": "Red", "kills": 8, "dmg": 1367}, "[U:1:95820688]": {"team": "Blue", "kills": 11, "dmg": 2595}, "[U:1:59977210]": {"team": "Red", "kills": 1, "dmg": 1222}, "[U:1:51723097]": {"team": "Blue", "kills": 2, "dmg": 872}, "[U:1:172534925]": {"team": "Blue", "kills": 2, "dmg": 1739}, "[U:1:118758944]": {"team": "Red", "kills": 8, "dmg": 2485}, "[U:1:172044269]": {"team": "Red", "kills": 7, "dmg": 2337}, "[U:1:167517704]": {"team": "Blue", "kills": 0, "dmg": 134}, "[U:1:247875068]": {"team": "Red", "kills": 0, "dmg": 75}}, "firstcap": "Red", "length": 468}, {"start_time": 1521143552, "winner": "Blue", "team": {"Blue": {"score": 1, "kills": 39, "dmg": 12878, "ubers": 4}, "Red": {"score": 2, "kills": 35, "dmg": 13456, "ubers": 6}}, "events": [{"type": "medic_death", "time": 982, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:59977210]"}, {"type": "pointcap", "time": 1013, "team": "Red", "point": 3}, {"type": "pointcap", "time": 1023, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 1053, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 1080, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:178869439]"}, {"type": "pointcap", "time": 1092, "team": "Blue", "point": 2}, {"type": "drop", "time": 1107, "team": "Blue", "steamid": "[U:1:167517704]"}, {"type": "medic_death", "time": 1107, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:172044269]"}, {"type": "pointcap", "time": 1117, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 1134, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 1228, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "charge", "medigun": "medigun", "time": 1234, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 1251, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "pointcap", "time": 1275, "team": "Red", "point": 4}, {"type": "pointcap", "time": 1296, "team": "Red", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 1355, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "charge", "medigun": "medigun", "time": 1355, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "charge", "medigun": "medigun", "time": 1422, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 1434, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:81145222]"}, {"type": "medic_death", "time": 1437, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:111776267]"}, {"type": "pointcap", "time": 1460, "team": "Blue", "point": 3}, {"type": "charge", "medigun": "kritzkrieg", "time": 1501, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "charge", "medigun": "medigun", "time": 1509, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 1514, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:204729823]"}, {"type": "pointcap", "time": 1526, "team": "Red", "point": 3}, {"type": "medic_death", "time": 1551, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:178869439]"}, {"type": "pointcap", "time": 1569, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 1601, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 1634, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "charge", "medigun": "medigun", "time": 1650, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "pointcap", "time": 1695, "team": "Blue", "point": 5}, {"type": "round_win", "time": 1695, "team": "Blue"}], "players": {"[U:1:111776267]": {"team": "Blue", "kills": 9, "dmg": 2461}, "[U:1:118758944]": {"team": "Red", "kills": 6, "dmg": 3254}, "[U:1:59977210]": {"team": "Red", "kills": 4, "dmg": 2475}, "[U:1:172044269]": {"team": "Red", "kills": 7, "dmg": 3075}, "[U:1:178869439]": {"team": "Blue", "kills": 8, "dmg": 2141}, "[U:1:51723097]": {"team": "Blue", "kills": 8, "dmg": 3044}, "[U:1:95820688]": {"team": "Blue", "kills": 8, "dmg": 2197}, "[U:1:204729823]": {"team": "Red", "kills": 9, "dmg": 1852}, "[U:1:81145222]": {"team": "Red", "kills": 8, "dmg": 2528}, "[U:1:172534925]": {"team": "Blue", "kills": 6, "dmg": 2899}, "[U:1:247875068]": {"team": "Red", "kills": 1, "dmg": 272}, "[U:1:167517704]": {"team": "Blue", "kills": 0, "dmg": 136}}, "firstcap": "Red", "length": 987}, {"start_time": 1521144549, "winner": "Red", "team": {"Blue": {"score": 1, "kills": 21, "dmg": 7584, "ubers": 2}, "Red": {"score": 2, "kills": 24, "dmg": 6801, "ubers": 1}}, "events": [{"type": "pointcap", "time": 1751, "team": "Red", "point": 3}, {"type": "medic_death", "time": 1762, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:81145222]"}, {"type": "pointcap", "time": 1795, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 1857, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "pointcap", "time": 1868, "team": "Blue", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 1876, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "pointcap", "time": 1877, "team": "Red", "point": 2}, {"type": "medic_death", "time": 1894, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:111776267]"}, {"type": "pointcap", "time": 1908, "team": "Blue", "point": 2}, {"type": "pointcap", "time": 1925, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 1943, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 1954, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "medic_death", "time": 1967, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:95820688]"}, {"type": "medic_death", "time": 1973, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "medic_death", "time": 2029, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:204729823]"}, {"type": "round_win", "time": 2048, "team": "Red"}], "players": {"[U:1:118758944]": {"team": "Red", "kills": 5, "dmg": 1712}, "[U:1:204729823]": {"team": "Red", "kills": 5, "dmg": 711}, "[U:1:111776267]": {"team": "Blue", "kills": 5, "dmg": 1083}, "[U:1:95820688]": {"team": "Blue", "kills": 7, "dmg": 1803}, "[U:1:59977210]": {"team": "Red", "kills": 1, "dmg": 942}, "[U:1:81145222]": {"team": "Red", "kills": 6, "dmg": 1719}, "[U:1:172534925]": {"team": "Blue", "kills": 1, "dmg": 1419}, "[U:1:172044269]": {"team": "Red", "kills": 6, "dmg": 1652}, "[U:1:51723097]": {"team": "Blue", "kills": 3, "dmg": 1678}, "[U:1:178869439]": {"team": "Blue", "kills": 5, "dmg": 1471}, "[U:1:167517704]": {"team": "Blue", "kills": 0, "dmg": 130}, "[U:1:247875068]": {"team": "Red", "kills": 1, "dmg": 65}}, "firstcap": "Red", "length": 343}], "healspread": {"[U:1:247875068]": {"[U:1:118758944]": 7586, "[U:1:59977210]": 3268, "[U:1:204729823]": 2905, "[U:1:81145222]": 5381, "[U:1:172044269]": 5515}, "[U:1:167517704]": {"[U:1:111776267]": 4005, "[U:1:178869439]": 5025, "[U:1:172534925]": 2358, "[U:1:95820688]": 5381, "[U:1:51723097]": 6856}}, "classkills": {"[U:1:178869439]": {"soldier": 8, "scout": 8, "demoman": 4, "medic": 2}, "[U:1:95820688]": {"demoman": 4, "soldier": 12, "scout": 6, "medic": 3, "sniper": 1, "pyro": 2}, "[U:1:111776267]": {"scout": 8, "medic": 3, "soldier": 8, "pyro": 1}, "[U:1:81145222]": {"scout": 8, "soldier": 9, "demoman": 4, "medic": 3}, "[U:1:118758944]": {"scout": 5, "soldier": 9, "heavyweapons": 1, "medic": 5, "sniper": 1, "demoman": 1, "pyro": 1}, "[U:1:59977210]": {"medic": 3, "soldier": 2, "scout": 2, "demoman": 1, "sniper": 1}, "[U:1:172044269]": {"scout": 3, "soldier": 10, "demoman": 4, "sniper": 1, "medic": 3, "pyro": 2}, "[U:1:204729823]": {"demoman": 7, "soldier": 9, "pyro": 1, "scout": 8, "medic": 2}, "[U:1:172534925]": {"scout": 3, "soldier": 6, "engineer": 1, "demoman": 1}, "[U:1:51723097]": {"soldier": 6, "scout": 3, "demoman": 4}, "[U:1:247875068]": {"scout": 1, "sniper": 1}}, "classdeaths": {"[U:1:59977210]": {"demoman": 5, "scout": 10, "sniper": 1, "soldier": 4}, "[U:1:118758944]": {"scout": 3, "sniper": 1, "demoman": 4, "soldier": 4, "pyro": 1}, "[U:1:204729823]": {"scout": 8, "soldier": 3, "sniper": 3, "heavyweapons": 1, "demoman": 3}, "[U:1:172044269]": {"scout": 7, "sniper": 2, "soldier": 8, "demoman": 3}, "[U:1:247875068]": {"scout": 5, "sniper": 1, "demoman": 2}, "[U:1:111776267]": {"scout": 9, "demoman": 4, "soldier": 4, "engineer": 1, "pyro": 1}, "[U:1:81145222]": {"demoman": 5, "soldier": 4, "scout": 5, "sniper": 1}, "[U:1:167517704]": {"soldier": 6, "demoman": 5, "scout": 4, "heavyweapons": 1}, "[U:1:51723097]": {"demoman": 4, "soldier": 9, "scout": 7}, "[U:1:172534925]": {"scout": 10, "demoman": 6, "soldier": 4, "heavyweapons": 1}, "[U:1:95820688]": {"soldier": 4, "scout": 4, "demoman": 3, "sniper": 1, "medic": 2, "engineer": 1}, "[U:1:178869439]": {"scout": 10, "soldier": 5, "sniper": 1, "demoman": 1}}, "classkillassists": {"[U:1:178869439]": {"soldier": 12, "scout": 10, "demoman": 5, "medic": 2}, "[U:1:111776267]": {"soldier": 14, "demoman": 4, "scout": 10, "medic": 4, "pyro": 1}, "[U:1:95820688]": {"demoman": 4, "soldier": 15, "scout": 9, "medic": 4, "sniper": 1, "pyro": 2}, "[U:1:51723097]": {"scout": 5, "soldier": 6, "demoman": 4}, "[U:1:167517704]": {"soldier": 5, "scout": 2, "demoman": 1, "pyro": 1}, "[U:1:81145222]": {"scout": 11, "soldier": 14, "medic": 7, "pyro": 3, "demoman": 7}, "[U:1:118758944]": {"scout": 8, "soldier": 12, "heavyweapons": 1, "medic": 7, "sniper": 1, "demoman": 1, "pyro": 1}, "[U:1:59977210]": {"scout": 3, "medic": 3, "demoman": 2, "heavyweapons": 1, "soldier": 3, "sniper": 1}, "[U:1:247875068]": {"medic": 2, "soldier": 5, "scout": 3, "demoman": 4, "sniper": 2}, "[U:1:204729823]": {"soldier": 12, "demoman": 8, "pyro": 1, "scout": 9, "medic": 3}, "[U:1:172044269]": {"scout": 5, "soldier": 11, "demoman": 4, "sniper": 1, "medic": 4, "pyro": 2}, "[U:1:172534925]": {"scout": 5, "soldier": 10, "engineer": 1, "demoman": 1, "medic": 1}}, "chat": [{"steamid": "Console", "name": "Console", "msg": "ETF2L config (2016-01-26) loaded."}, {"steamid": "Console", "name": "Console", "msg": "* Please check that the settings are correct for this game mode!"}, {"steamid": "Console", "name": "Console", "msg": "* You must record POV demos and take screenshots of all results."}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "lavaaa"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "Yes"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "hello"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "wadu hek?"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "Helol"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": ":)"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": ":>"}, {"steamid": "[U:1:95820688]", "name": "Dominant", "msg": "We are so nervous guys"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "deb0ut : aberta down"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "wadu hek?"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "hI Sage"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "hi"}, {"steamid": "[U:1:51723097]", "name": "sage LF demo 6s", "msg": "ohaiyo~"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "HI everyone Else"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "ello"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": "if we win, can a please be moved to faceit ametur finally? please"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "LOL"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "wait ur not supposed to be playing rn"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "NA only"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": ":thinking:"}, {"steamid": "[U:1:51723097]", "name": "sage LF demo 6s", "msg": "hes NA"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "oh"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "right right.."}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "i have a 144hz screen now im esl csgo level"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "we are na"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "im too hehe"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "im 100% na"}, {"steamid": "[U:1:51723097]", "name": "sage LF demo 6s", "msg": "hihi"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "gringo here"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": "lmfao"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "wanderlust ur SA?"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "exposed"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "dont screenshot this: tf2pl coming south america"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "SA = saudi arabian"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "exposed"}, {"steamid": "[U:1:51723097]", "name": "sage LF demo 6s", "msg": "SA = Silly Animelord"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "REALLY"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": "lmfao"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "PLEASE"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": ":)"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "I WANNA PLAY IN NA"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "NO"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "RIp"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "WE ALL KNOW EACH OTHER IN SA"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "ITS SHIT"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "now u get to play for points xd"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "anime is shit"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "!!"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "ur face is shit johnny"}, {"steamid": "[U:1:95820688]", "name": "Dominant", "msg": "40k faceit points "}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "mge bitch"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": "toxic euros"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "im sorry i am just european"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "im not good"}, {"steamid": "[U:1:204729823]", "name": "KoOoOOdEEeEeeY", "msg": "same"}, {"steamid": "[U:1:204729823]", "name": "KoOoOOdEEeEeeY", "msg": "large"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "large frags"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "i just got our pyto"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "out pyros"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "slam ya sen"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "slam"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "zaidu my love"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "by7==7yatj tfoz xd"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "wadu hek?"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "b7yatk tfoz "}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "monkaS"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "frek msh mne7 had"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "tshof"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": ":<"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": ":) "}, {"steamid": "[U:1:95820688]", "name": "Dominant", "msg": "gl hf"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "i literally"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "have 40 fps"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "right now"}, {"steamid": "[U:1:204729823]", "name": "KoOoOOdEEeEeeY", "msg": "lmao"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "lol"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "i was there for 5 minutes"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "dont look 1 sec"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "someone comes threw"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "7.5k"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "Pog"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "wadu hek?"}, {"steamid": "[U:1:51723097]", "name": "sage LF demo 6s", "msg": "can we pause "}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "sure"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "sure"}, {"steamid": "[U:1:81145222]", "name": "ash", "msg": "whats up?"}, {"steamid": "[U:1:95820688]", "name": "Dominant", "msg": "No clue"}, {"steamid": "[U:1:81145222]", "name": "ash", "msg": "restart?"}, {"steamid": "[U:1:81145222]", "name": "ash", "msg": "pc?"}, {"steamid": "[U:1:51723097]", "name": "sage LF demo 6s", "msg": "laptop gamer has 40 fps"}, {"steamid": "[U:1:81145222]", "name": "ash", "msg": "game?"}, {"steamid": "[U:1:81145222]", "name": "ash", "msg": "oh rip"}, {"steamid": "[U:1:81145222]", "name": "ash", "msg": "i know the feel"}, {"steamid": "[U:1:81145222]", "name": "ash", "msg": "my RAM died recently"}, {"steamid": "[U:1:204729823]", "name": "KoOoOOdEEeEeeY", "msg": "i have to overclock my gpu to get playable performance"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "overclock my penile member"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "aka overcock"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "can u get a merc"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "press G for GG"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "we unpausing"}, {"steamid": "[U:1:204729823]", "name": "KoOoOOdEEeEeeY", "msg": "ook"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "xd"}, {"steamid": "[U:1:172044269]", "name": "eldoccc", "msg": "why"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "med lucky."}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "luicky med"}, {"steamid": "[U:1:172044269]", "name": "eldoccc", "msg": "noone ever check there"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "gr"}, {"steamid": "[U:1:204729823]", "name": "KoOoOOdEEeEeeY", "msg": "lmao"}, {"steamid": "[U:1:172044269]", "name": "eldoccc", "msg": "WHY"}, {"steamid": "[U:1:172044269]", "name": "eldoccc", "msg": "RETARDS"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "wadu hek?"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": ":)_"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": ":("}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "gg"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "gg"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "gg"}, {"steamid": "[U:1:172044269]", "name": "eldoccc", "msg": "gg"}], "info": {"map": "cp_prolands_b3b", "supplemental": true, "total_length": 2018, "hasRealDamage": true, "hasWeaponDamage": true, "hasAccuracy": false, "hasHP": true, "hasHP_real": true, "hasHS": true, "hasHS_hit": true, "hasBS": false, "hasCP": true, "hasSB": false, "hasDT": true, "hasAS": true, "hasHR": true, "hasIntel": false, "AD_scoring": false, "notifications": [], "title": "serveme.tf #769415 - BLU vs RED", "date": 1521144904, "uploader": {"id": "76561197960497430", "name": "Arie - VanillaTF2.org", "info": "TFTrue v4.79"}}, "killstreaks": [{"steamid": "[U:1:81145222]", "streak": 3, "time": 347}, {"steamid": "[U:1:95820688]", "streak": 3, "time": 422}, {"steamid": "[U:1:51723097]", "streak": 3, "time": 1067}, {"steamid": "[U:1:204729823]", "streak": 4, "time": 985}, {"steamid": "[U:1:81145222]", "streak": 4, "time": 1762}], "success": true}');

    select import_logs('i63', '1983350', '{"version": 3, "teams": {"Red": {"score": 2, "kills": 100, "deaths": 0, "dmg": 36169, "charges": 13, "drops": 0, "firstcaps": 3, "caps": 16}, "Blue": {"score": 3, "kills": 111, "deaths": 0, "dmg": 35060, "charges": 12, "drops": 1, "firstcaps": 2, "caps": 18}}, "length": 1756, "players": {"[U:1:178869439]": {"team": "Blue", "class_stats": [{"type": "demoman", "kills": 15, "assists": 8, "deaths": 15, "dmg": 6801, "weapon": {"tf_projectile_pipe_remote": {"kills": 11, "dmg": 4314, "avg_dmg": 59.0958904109589, "shots": 0, "hits": 0}, "tf_projectile_pipe": {"kills": 4, "dmg": 2487, "avg_dmg": 77.71875, "shots": 0, "hits": 0}}, "total_time": 1755}], "kills": 15, "deaths": 15, "assists": 8, "suicides": 0, "kapd": "1.5", "kpd": "1.0", "dmg": 6801, "dmg_real": 683, "dt": 6121, "dt_real": 2015, "hr": 6950, "lks": 7, "as": 4, "dapd": 453, "dapm": 232, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 39, "medkits_hp": 1328, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 1651, "cpc": 4, "ic": 0, "medicstats": {"avg_uber_length": 1420.7019230769235}}, "[U:1:59977210]": {"team": "Red", "class_stats": [{"type": "soldier", "kills": 16, "assists": 2, "deaths": 25, "dmg": 6835, "weapon": {"tf_projectile_rocket": {"kills": 14, "dmg": 6835, "avg_dmg": 64.48113207547169, "shots": 0, "hits": 0}, "world": {"kills": 2, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1748}], "kills": 16, "deaths": 25, "assists": 2, "suicides": 0, "kapd": "0.7", "kpd": "0.6", "dmg": 6835, "dmg_real": 570, "dt": 6494, "dt_real": 1902, "hr": 3023, "lks": 3, "as": 3, "dapd": 273, "dapm": 233, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 76, "medkits_hp": 2652, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 9, "ic": 0}, "[U:1:51723097]": {"team": "Blue", "class_stats": [{"type": "soldier", "kills": 20, "assists": 4, "deaths": 17, "dmg": 6080, "weapon": {"tf_projectile_rocket": {"kills": 6, "dmg": 3327, "avg_dmg": 57.36206896551724, "shots": 0, "hits": 0}, "shotgun_soldier": {"kills": 7, "dmg": 616, "avg_dmg": 28, "shots": 0, "hits": 0}, "quake_rl": {"kills": 7, "dmg": 2137, "avg_dmg": 66.78125, "shots": 0, "hits": 0}}, "total_time": 1640}, {"type": "sniper", "kills": 1, "assists": 0, "deaths": 1, "dmg": 605, "weapon": {"sniperrifle": {"kills": 1, "dmg": 600, "avg_dmg": 300, "shots": 0, "hits": 0}, "smg": {"kills": 0, "dmg": 5, "avg_dmg": 5, "shots": 0, "hits": 0}}, "total_time": 117}], "kills": 21, "deaths": 18, "assists": 4, "suicides": 0, "kapd": "1.4", "kpd": "1.2", "dmg": 6685, "dmg_real": 1245, "dt": 6340, "dt_real": 745, "hr": 5507, "lks": 3, "as": 4, "dapd": 371, "dapm": 228, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 56, "medkits_hp": 2014, "backstabs": 0, "headshots": 1, "headshots_hit": 2, "sentries": 0, "heal": 3254, "cpc": 8, "ic": 0}, "[U:1:204729823]": {"team": "Red", "class_stats": [{"type": "scout", "kills": 17, "assists": 8, "deaths": 22, "dmg": 5935, "weapon": {"scattergun": {"kills": 16, "dmg": 5842, "avg_dmg": 28.22222222222222, "shots": 0, "hits": 0}, "the_capper": {"kills": 1, "dmg": 93, "avg_dmg": 15.5, "shots": 0, "hits": 0}}, "total_time": 1637}, {"type": "sniper", "kills": 1, "assists": 1, "deaths": 1, "dmg": 159, "weapon": {"sniperrifle": {"kills": 1, "dmg": 150, "avg_dmg": 150, "shots": 0, "hits": 0}, "smg": {"kills": 0, "dmg": 9, "avg_dmg": 9, "shots": 0, "hits": 0}}, "total_time": 72}], "kills": 18, "deaths": 23, "assists": 9, "suicides": 0, "kapd": "1.2", "kpd": "0.8", "dmg": 6142, "dmg_real": 1247, "dt": 4772, "dt_real": 754, "hr": 3189, "lks": 3, "as": 0, "dapd": 267, "dapm": 209, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 22, "medkits_hp": 495, "backstabs": 0, "headshots": 1, "headshots_hit": 1, "sentries": 0, "heal": 9074, "cpc": 3, "ic": 0}, "[U:1:95820688]": {"team": "Blue", "class_stats": [{"type": "scout", "kills": 34, "assists": 10, "deaths": 14, "dmg": 6475, "weapon": {"scattergun": {"kills": 28, "dmg": 6337, "avg_dmg": 34.44021739130435, "shots": 0, "hits": 0}, "world": {"kills": 4, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}, "boston_basher": {"kills": 0, "dmg": 39, "avg_dmg": 19.5, "shots": 0, "hits": 0}, "bleed_kill": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}, "the_capper": {"kills": 1, "dmg": 99, "avg_dmg": 16.5, "shots": 0, "hits": 0}}, "total_time": 1482}, {"type": "sniper", "kills": 4, "assists": 1, "deaths": 2, "dmg": 1561, "weapon": {"sniperrifle": {"kills": 4, "dmg": 1531, "avg_dmg": 191.375, "shots": 0, "hits": 0}, "smg": {"kills": 0, "dmg": 30, "avg_dmg": 10, "shots": 0, "hits": 0}}, "total_time": 275}], "kills": 38, "deaths": 16, "assists": 11, "suicides": 0, "kapd": "3.1", "kpd": "2.4", "dmg": 8036, "dmg_real": 3251, "dt": 5906, "dt_real": 756, "hr": 5701, "lks": 9, "as": 0, "dapd": 502, "dapm": 274, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 9, "medkits_hp": 178, "backstabs": 0, "headshots": 3, "headshots_hit": 3, "sentries": 0, "heal": 4406, "cpc": 9, "ic": 0}, "[U:1:81145222]": {"team": "Red", "class_stats": [{"type": "scout", "kills": 24, "assists": 8, "deaths": 13, "dmg": 5456, "weapon": {"scattergun": {"kills": 18, "dmg": 5012, "avg_dmg": 23.203703703703702, "shots": 0, "hits": 0}, "pistol_scout": {"kills": 6, "dmg": 444, "avg_dmg": 17.76, "shots": 0, "hits": 0}}, "total_time": 1377}, {"type": "engineer", "kills": 2, "assists": 0, "deaths": 0, "dmg": 553, "weapon": {"obj_sentrygun3": {"kills": 1, "dmg": 407, "avg_dmg": 16.28, "shots": 0, "hits": 0}, "shotgun_primary": {"kills": 0, "dmg": 128, "avg_dmg": 16, "shots": 0, "hits": 0}, "pistol": {"kills": 1, "dmg": 18, "avg_dmg": 9, "shots": 0, "hits": 0}}, "total_time": 203}, {"type": "sniper", "kills": 1, "assists": 0, "deaths": 1, "dmg": 600, "weapon": {"awper_hand": {"kills": 1, "dmg": 600, "avg_dmg": 150, "shots": 0, "hits": 0}}, "total_time": 75}, {"type": "heavyweapons", "kills": 1, "assists": 0, "deaths": 1, "dmg": 75, "weapon": {"tomislav": {"kills": 1, "dmg": 75, "avg_dmg": 5.769230769230769, "shots": 0, "hits": 0}}, "total_time": 55}, {"type": "pyro", "kills": 3, "assists": 0, "deaths": 1, "dmg": 404, "weapon": {"flamethrower": {"kills": 3, "dmg": 404, "avg_dmg": 9.619047619047619, "shots": 0, "hits": 0}}, "total_time": 43}], "kills": 31, "deaths": 16, "assists": 8, "suicides": 0, "kapd": "2.4", "kpd": "1.9", "dmg": 7088, "dmg_real": 1729, "dt": 4896, "dt_real": 596, "hr": 4489, "lks": 5, "as": 0, "dapd": 443, "dapm": 242, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 12, "medkits_hp": 312, "backstabs": 0, "headshots": 1, "headshots_hit": 2, "sentries": 0, "heal": 0, "cpc": 9, "ic": 0}, "[U:1:172534925]": {"team": "Blue", "class_stats": [{"type": "soldier", "kills": 12, "assists": 10, "deaths": 19, "dmg": 7080, "weapon": {"tf_projectile_rocket": {"kills": 10, "dmg": 7080, "avg_dmg": 57.5609756097561, "shots": 0, "hits": 0}, "world": {"kills": 2, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1755}], "kills": 12, "deaths": 19, "assists": 10, "suicides": 0, "kapd": "1.2", "kpd": "0.6", "dmg": 7080, "dmg_real": 349, "dt": 7289, "dt_real": 735, "hr": 3762, "lks": 5, "as": 4, "dapd": 372, "dapm": 241, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 117, "medkits_hp": 3855, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 2931, "cpc": 5, "ic": 0}, "[U:1:111776267]": {"team": "Blue", "class_stats": [{"type": "scout", "kills": 21, "assists": 8, "deaths": 19, "dmg": 5649, "weapon": {"scattergun": {"kills": 17, "dmg": 5234, "avg_dmg": 22.756521739130434, "shots": 0, "hits": 0}, "maxgun": {"kills": 3, "dmg": 415, "avg_dmg": 11.527777777777779, "shots": 0, "hits": 0}, "world": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1725}, {"type": "heavyweapons", "kills": 0, "assists": 0, "deaths": 1, "dmg": 10, "weapon": {"minigun": {"kills": 0, "dmg": 10, "avg_dmg": 10, "shots": 0, "hits": 0}}, "total_time": 32}], "kills": 21, "deaths": 20, "assists": 8, "suicides": 0, "kapd": "1.4", "kpd": "1.1", "dmg": 5659, "dmg_real": 2093, "dt": 6085, "dt_real": 615, "hr": 4214, "lks": 5, "as": 0, "dapd": 282, "dapm": 193, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 33, "medkits_hp": 693, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 4304, "cpc": 12, "ic": 0}, "[U:1:172044269]": {"team": "Red", "class_stats": [{"type": "soldier", "kills": 16, "assists": 9, "deaths": 20, "dmg": 6917, "weapon": {"quake_rl": {"kills": 16, "dmg": 6917, "avg_dmg": 61.21238938053097, "shots": 0, "hits": 0}}, "total_time": 1757}], "kills": 16, "deaths": 20, "assists": 9, "suicides": 0, "kapd": "1.3", "kpd": "0.8", "dmg": 6917, "dmg_real": 754, "dt": 7074, "dt_real": 833, "hr": 5772, "lks": 3, "as": 3, "dapd": 345, "dapm": 236, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 64, "medkits_hp": 2092, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 2, "ic": 0}, "[U:1:247875068]": {"team": "Red", "class_stats": [{"type": "medic", "kills": 1, "assists": 12, "deaths": 10, "dmg": 504, "weapon": {"crusaders_crossbow": {"kills": 0, "dmg": 309, "avg_dmg": 44.142857142857146, "shots": 0, "hits": 0}, "ubersaw": {"kills": 1, "dmg": 195, "avg_dmg": 65, "shots": 0, "hits": 0}}, "total_time": 1757}], "kills": 1, "deaths": 10, "assists": 12, "suicides": 0, "kapd": "1.3", "kpd": "0.1", "dmg": 504, "dmg_real": 73, "dt": 3535, "dt_real": 477, "hr": 0, "lks": 1, "as": 0, "dapd": 50, "dapm": 17, "ubers": 13, "ubertypes": {"medigun": 13}, "drops": 0, "medkits": 11, "medkits_hp": 335, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 24978, "cpc": 5, "ic": 0, "medicstats": {"advantages_lost": 2, "biggest_advantage_lost": 151, "deaths_with_95_99_uber": 0, "deaths_within_20s_after_uber": 5, "avg_time_before_healing": 11.261538461538462, "avg_time_to_build": 64.23076923076923, "avg_time_before_using": 31.692307692307693, "avg_uber_length": 7.184615384615385}}, "[U:1:118758944]": {"team": "Red", "class_stats": [{"type": "demoman", "kills": 18, "assists": 6, "deaths": 17, "dmg": 8683, "weapon": {"tf_projectile_pipe_remote": {"kills": 10, "dmg": 5978, "avg_dmg": 58.6078431372549, "shots": 0, "hits": 0}, "tf_projectile_pipe": {"kills": 8, "dmg": 2705, "avg_dmg": 71.1842105263158, "shots": 0, "hits": 0}}, "total_time": 1757}], "kills": 18, "deaths": 17, "assists": 6, "suicides": 0, "kapd": "1.4", "kpd": "1.1", "dmg": 8683, "dmg_real": 894, "dt": 8289, "dt_real": 3379, "hr": 8417, "lks": 5, "as": 3, "dapd": 510, "dapm": 296, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 23, "medkits_hp": 765, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 6763, "cpc": 5, "ic": 0}, "[U:1:167517704]": {"team": "Blue", "class_stats": [{"type": "medic", "kills": 4, "assists": 11, "deaths": 12, "dmg": 799, "weapon": {"crusaders_crossbow": {"kills": 4, "dmg": 799, "avg_dmg": 57.07142857142857, "shots": 0, "hits": 0}}, "total_time": 1757}], "kills": 4, "deaths": 12, "assists": 11, "suicides": 0, "kapd": "1.3", "kpd": "0.3", "dmg": 799, "dmg_real": 320, "dt": 4428, "dt_real": 401, "hr": 0, "lks": 2, "as": 0, "dapd": 66, "dapm": 27, "ubers": 12, "ubertypes": {"medigun": 12}, "drops": 1, "medkits": 9, "medkits_hp": 244, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 26479, "cpc": 9, "ic": 0, "medicstats": {"deaths_with_95_99_uber": 0, "advantages_lost": 2, "biggest_advantage_lost": 22, "deaths_within_20s_after_uber": 4, "avg_time_before_healing": 9.341176470588234, "avg_time_to_build": 71.24615384615385, "avg_time_before_using": 32, "avg_uber_length": 6.65}}}, "names": {"[U:1:178869439]": "herpestim", "[U:1:59977210]": "twiikuu | tf2.gg tf2pl.com", "[U:1:51723097]": "sage LF demo 6s", "[U:1:204729823]": "KoOoOOdEEeEeeY", "[U:1:95820688]": "Dominant", "[U:1:81145222]": "ash", "[U:1:172534925]": "_Sen", "[U:1:111776267]": "wanderlust_", "[U:1:172044269]": "eldoccc", "[U:1:247875068]": "Zaid", "[U:1:118758944]": "Lava", "[U:1:167517704]": "Beelthazus"}, "rounds": [{"start_time": 1521145356, "winner": "Red", "team": {"Blue": {"score": 0, "kills": 2, "dmg": 1363, "ubers": 0}, "Red": {"score": 1, "kills": 8, "dmg": 2524, "ubers": 1}}, "events": [{"type": "medic_death", "time": 38, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:59977210]"}, {"type": "pointcap", "time": 55, "team": "Red", "point": 3}, {"type": "pointcap", "time": 62, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 81, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "pointcap", "time": 92, "team": "Red", "point": 1}, {"type": "round_win", "time": 92, "team": "Red"}], "players": {"[U:1:81145222]": {"team": "Red", "kills": 2, "dmg": 861}, "[U:1:204729823]": {"team": "Red", "kills": 2, "dmg": 548}, "[U:1:111776267]": {"team": "Blue", "kills": 0, "dmg": 171}, "[U:1:59977210]": {"team": "Red", "kills": 3, "dmg": 787}, "[U:1:167517704]": {"team": "Blue", "kills": 0, "dmg": 67}, "[U:1:118758944]": {"team": "Red", "kills": 0, "dmg": 230}, "[U:1:51723097]": {"team": "Blue", "kills": 0, "dmg": 166}, "[U:1:95820688]": {"team": "Blue", "kills": 2, "dmg": 662}, "[U:1:172534925]": {"team": "Blue", "kills": 0, "dmg": 179}, "[U:1:178869439]": {"team": "Blue", "kills": 0, "dmg": 118}, "[U:1:172044269]": {"team": "Red", "kills": 1, "dmg": 98}, "[U:1:247875068]": {"team": "Red", "kills": 0, "dmg": 0}}, "firstcap": "Red", "length": 91}, {"start_time": 1521145457, "winner": "Blue", "team": {"Blue": {"score": 1, "kills": 42, "dmg": 14654, "ubers": 5}, "Red": {"score": 1, "kills": 32, "dmg": 13481, "ubers": 5}}, "events": [{"type": "pointcap", "time": 146, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 159, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 246, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "pointcap", "time": 284, "team": "Red", "point": 4}, {"type": "pointcap", "time": 317, "team": "Red", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 359, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "charge", "medigun": "medigun", "time": 362, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 388, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:95820688]"}, {"type": "pointcap", "time": 400, "team": "Blue", "point": 3}, {"type": "medic_death", "time": 412, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:204729823]"}, {"type": "medic_death", "time": 448, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:81145222]"}, {"type": "charge", "medigun": "medigun", "time": 529, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "pointcap", "time": 530, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 564, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "medic_death", "time": 572, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "pointcap", "time": 599, "team": "Red", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 613, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 620, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "pointcap", "time": 644, "team": "Red", "point": 3}, {"type": "pointcap", "time": 655, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 704, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "charge", "medigun": "medigun", "time": 707, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "medic_death", "time": 717, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:172534925]"}, {"type": "pointcap", "time": 732, "team": "Blue", "point": 2}, {"type": "pointcap", "time": 758, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 781, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 819, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "charge", "medigun": "medigun", "time": 825, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "pointcap", "time": 839, "team": "Blue", "point": 5}, {"type": "round_win", "time": 839, "team": "Blue"}], "players": {"[U:1:178869439]": {"team": "Blue", "kills": 5, "dmg": 3250}, "[U:1:118758944]": {"team": "Red", "kills": 6, "dmg": 2881}, "[U:1:111776267]": {"team": "Blue", "kills": 8, "dmg": 2322}, "[U:1:95820688]": {"team": "Blue", "kills": 18, "dmg": 3482}, "[U:1:81145222]": {"team": "Red", "kills": 12, "dmg": 2259}, "[U:1:204729823]": {"team": "Red", "kills": 7, "dmg": 2624}, "[U:1:172534925]": {"team": "Blue", "kills": 3, "dmg": 2725}, "[U:1:51723097]": {"team": "Blue", "kills": 7, "dmg": 2767}, "[U:1:172044269]": {"team": "Red", "kills": 2, "dmg": 2993}, "[U:1:59977210]": {"team": "Red", "kills": 4, "dmg": 2450}, "[U:1:167517704]": {"team": "Blue", "kills": 1, "dmg": 108}, "[U:1:247875068]": {"team": "Red", "kills": 1, "dmg": 274}}, "firstcap": "Blue", "length": 737}, {"start_time": 1521146204, "winner": "Blue", "team": {"Blue": {"score": 2, "kills": 18, "dmg": 4774, "ubers": 2}, "Red": {"score": 1, "kills": 10, "dmg": 4563, "ubers": 2}}, "events": [{"type": "pointcap", "time": 895, "team": "Red", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 919, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "charge", "medigun": "medigun", "time": 923, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "medic_death", "time": 928, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:95820688]"}, {"type": "pointcap", "time": 942, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 961, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 1025, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "charge", "medigun": "medigun", "time": 1027, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "medic_death", "time": 1041, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:81145222]"}, {"type": "medic_death", "time": 1043, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:51723097]"}, {"type": "pointcap", "time": 1045, "team": "Blue", "point": 5}, {"type": "round_win", "time": 1045, "team": "Blue"}], "players": {"[U:1:118758944]": {"team": "Red", "kills": 3, "dmg": 1053}, "[U:1:178869439]": {"team": "Blue", "kills": 5, "dmg": 1214}, "[U:1:95820688]": {"team": "Blue", "kills": 6, "dmg": 1476}, "[U:1:111776267]": {"team": "Blue", "kills": 1, "dmg": 466}, "[U:1:81145222]": {"team": "Red", "kills": 4, "dmg": 1125}, "[U:1:204729823]": {"team": "Red", "kills": 1, "dmg": 888}, "[U:1:167517704]": {"team": "Blue", "kills": 2, "dmg": 258}, "[U:1:51723097]": {"team": "Blue", "kills": 3, "dmg": 758}, "[U:1:172044269]": {"team": "Red", "kills": 1, "dmg": 513}, "[U:1:172534925]": {"team": "Blue", "kills": 1, "dmg": 602}, "[U:1:59977210]": {"team": "Red", "kills": 1, "dmg": 984}, "[U:1:247875068]": {"team": "Red", "kills": 0, "dmg": 0}}, "firstcap": "Red", "length": 196}, {"start_time": 1521146410, "winner": "Red", "team": {"Blue": {"score": 2, "kills": 23, "dmg": 6693, "ubers": 2}, "Red": {"score": 2, "kills": 23, "dmg": 7470, "ubers": 2}}, "events": [{"type": "medic_death", "time": 1093, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:172534925]"}, {"type": "pointcap", "time": 1126, "team": "Blue", "point": 3}, {"type": "drop", "time": 1156, "team": "Blue", "steamid": "[U:1:167517704]"}, {"type": "medic_death", "time": 1156, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:172044269]"}, {"type": "medic_death", "time": 1158, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:178869439]"}, {"type": "pointcap", "time": 1188, "team": "Red", "point": 3}, {"type": "pointcap", "time": 1207, "team": "Blue", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 1244, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "pointcap", "time": 1256, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 1268, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "pointcap", "time": 1285, "team": "Red", "point": 4}, {"type": "medic_death", "time": 1303, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:81145222]"}, {"type": "pointcap", "time": 1317, "team": "Red", "point": 3}, {"type": "pointcap", "time": 1332, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 1343, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 1354, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:172534925]"}, {"type": "charge", "medigun": "medigun", "time": 1388, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "pointcap", "time": 1391, "team": "Red", "point": 1}, {"type": "round_win", "time": 1391, "team": "Red"}], "players": {"[U:1:81145222]": {"team": "Red", "kills": 6, "dmg": 1515}, "[U:1:204729823]": {"team": "Red", "kills": 4, "dmg": 1123}, "[U:1:95820688]": {"team": "Blue", "kills": 6, "dmg": 1252}, "[U:1:111776267]": {"team": "Blue", "kills": 4, "dmg": 1206}, "[U:1:118758944]": {"team": "Red", "kills": 3, "dmg": 1630}, "[U:1:172534925]": {"team": "Blue", "kills": 4, "dmg": 1785}, "[U:1:59977210]": {"team": "Red", "kills": 3, "dmg": 1395}, "[U:1:51723097]": {"team": "Blue", "kills": 4, "dmg": 1202}, "[U:1:172044269]": {"team": "Red", "kills": 7, "dmg": 1759}, "[U:1:178869439]": {"team": "Blue", "kills": 4, "dmg": 992}, "[U:1:167517704]": {"team": "Blue", "kills": 1, "dmg": 256}, "[U:1:247875068]": {"team": "Red", "kills": 0, "dmg": 48}}, "firstcap": "Blue", "length": 336}, {"start_time": 1521146756, "winner": "Blue", "team": {"Blue": {"score": 3, "kills": 26, "dmg": 7576, "ubers": 3}, "Red": {"score": 2, "kills": 27, "dmg": 8131, "ubers": 3}}, "events": [{"type": "medic_death", "time": 1437, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "pointcap", "time": 1474, "team": "Red", "point": 3}, {"type": "medic_death", "time": 1490, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:118758944]"}, {"type": "charge", "medigun": "medigun", "time": 1490, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 1509, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:51723097]"}, {"type": "pointcap", "time": 1548, "team": "Blue", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 1575, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "medic_death", "time": 1585, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:204729823]"}, {"type": "charge", "medigun": "medigun", "time": 1612, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "pointcap", "time": 1623, "team": "Red", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 1679, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "charge", "medigun": "medigun", "time": 1682, "steamid": "[U:1:247875068]", "team": "Red"}, {"type": "medic_death", "time": 1693, "team": "Blue", "steamid": "[U:1:167517704]", "killer": "[U:1:81145222]"}, {"type": "medic_death", "time": 1724, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:95820688]"}, {"type": "pointcap", "time": 1745, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 1782, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 1788, "steamid": "[U:1:167517704]", "team": "Blue"}, {"type": "medic_death", "time": 1790, "team": "Red", "steamid": "[U:1:247875068]", "killer": "[U:1:111776267]"}, {"type": "pointcap", "time": 1797, "team": "Blue", "point": 5}, {"type": "round_win", "time": 1797, "team": "Blue"}], "players": {"[U:1:118758944]": {"team": "Red", "kills": 6, "dmg": 2889}, "[U:1:81145222]": {"team": "Red", "kills": 7, "dmg": 1328}, "[U:1:95820688]": {"team": "Blue", "kills": 6, "dmg": 1164}, "[U:1:111776267]": {"team": "Blue", "kills": 8, "dmg": 1494}, "[U:1:204729823]": {"team": "Red", "kills": 4, "dmg": 959}, "[U:1:178869439]": {"team": "Blue", "kills": 1, "dmg": 1227}, "[U:1:59977210]": {"team": "Red", "kills": 5, "dmg": 1219}, "[U:1:51723097]": {"team": "Blue", "kills": 7, "dmg": 1792}, "[U:1:172534925]": {"team": "Blue", "kills": 4, "dmg": 1789}, "[U:1:247875068]": {"team": "Red", "kills": 0, "dmg": 182}, "[U:1:167517704]": {"team": "Blue", "kills": 0, "dmg": 110}, "[U:1:172044269]": {"team": "Red", "kills": 5, "dmg": 1554}}, "firstcap": "Red", "length": 396}], "healspread": {"[U:1:167517704]": {"[U:1:178869439]": 6950, "[U:1:172534925]": 3762, "[U:1:111776267]": 4214, "[U:1:51723097]": 5507, "[U:1:95820688]": 5701}, "[U:1:247875068]": {"[U:1:118758944]": 8417, "[U:1:59977210]": 3023, "[U:1:204729823]": 3189, "[U:1:81145222]": 4489, "[U:1:172044269]": 5772}}, "classkills": {"[U:1:59977210]": {"demoman": 3, "soldier": 7, "medic": 1, "scout": 5}, "[U:1:81145222]": {"soldier": 11, "heavyweapons": 1, "demoman": 5, "scout": 10, "medic": 4}, "[U:1:204729823]": {"scout": 6, "sniper": 2, "soldier": 8, "medic": 2}, "[U:1:95820688]": {"demoman": 6, "scout": 10, "soldier": 18, "medic": 3, "sniper": 1}, "[U:1:172044269]": {"demoman": 5, "soldier": 6, "medic": 1, "scout": 4}, "[U:1:51723097]": {"scout": 6, "demoman": 5, "soldier": 8, "medic": 2}, "[U:1:111776267]": {"soldier": 9, "scout": 8, "demoman": 2, "medic": 1, "pyro": 1}, "[U:1:118758944]": {"scout": 8, "soldier": 4, "medic": 4, "sniper": 1, "demoman": 1}, "[U:1:167517704]": {"scout": 1, "soldier": 2, "demoman": 1}, "[U:1:178869439]": {"scout": 6, "soldier": 5, "heavyweapons": 1, "demoman": 2, "medic": 1}, "[U:1:172534925]": {"soldier": 3, "scout": 4, "medic": 3, "sniper": 1, "demoman": 1}, "[U:1:247875068]": {"demoman": 1}}, "classdeaths": {"[U:1:178869439]": {"soldier": 8, "engineer": 1, "medic": 1, "scout": 4, "demoman": 1}, "[U:1:51723097]": {"scout": 8, "soldier": 5, "demoman": 3, "pyro": 1, "sniper": 1}, "[U:1:111776267]": {"scout": 9, "demoman": 2, "engineer": 1, "soldier": 6, "pyro": 1, "heavyweapons": 1}, "[U:1:172534925]": {"soldier": 8, "scout": 8, "pyro": 1, "sniper": 1, "demoman": 1}, "[U:1:95820688]": {"scout": 6, "demoman": 7, "soldier": 3}, "[U:1:167517704]": {"soldier": 2, "scout": 6, "demoman": 4}, "[U:1:118758944]": {"sniper": 3, "scout": 6, "soldier": 5, "medic": 1, "demoman": 2}, "[U:1:204729823]": {"scout": 12, "soldier": 7, "medic": 1, "demoman": 3}, "[U:1:172044269]": {"scout": 11, "demoman": 3, "sniper": 2, "soldier": 4}, "[U:1:59977210]": {"scout": 14, "soldier": 7, "medic": 2, "demoman": 2}, "[U:1:81145222]": {"scout": 8, "demoman": 4, "soldier": 4}, "[U:1:247875068]": {"scout": 4, "soldier": 5, "demoman": 1}}, "classkillassists": {"[U:1:59977210]": {"demoman": 4, "soldier": 7, "medic": 2, "scout": 5}, "[U:1:81145222]": {"soldier": 15, "scout": 13, "heavyweapons": 1, "demoman": 6, "medic": 4}, "[U:1:204729823]": {"scout": 6, "demoman": 3, "soldier": 14, "sniper": 2, "medic": 2}, "[U:1:118758944]": {"scout": 12, "soldier": 5, "medic": 4, "sniper": 1, "demoman": 2}, "[U:1:95820688]": {"demoman": 8, "scout": 11, "soldier": 23, "medic": 5, "sniper": 1, "heavyweapons": 1}, "[U:1:178869439]": {"demoman": 4, "soldier": 8, "scout": 7, "heavyweapons": 1, "medic": 2, "pyro": 1}, "[U:1:247875068]": {"heavyweapons": 1, "soldier": 3, "scout": 5, "medic": 3, "demoman": 1}, "[U:1:172534925]": {"scout": 10, "soldier": 5, "medic": 3, "demoman": 3, "sniper": 1}, "[U:1:172044269]": {"demoman": 6, "medic": 3, "soldier": 9, "scout": 7}, "[U:1:51723097]": {"scout": 6, "demoman": 6, "soldier": 11, "medic": 2}, "[U:1:111776267]": {"soldier": 13, "scout": 11, "demoman": 2, "sniper": 1, "medic": 1, "pyro": 1}, "[U:1:167517704]": {"soldier": 8, "scout": 5, "demoman": 1, "medic": 1}}, "chat": [{"steamid": "Console", "name": "Console", "msg": "ETF2L config (2016-01-26) loaded."}, {"steamid": "Console", "name": "Console", "msg": "* Please check that the settings are correct for this game mode!"}, {"steamid": "Console", "name": "Console", "msg": "* You must record POV demos and take screenshots of all results."}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "guys"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "we need a new server"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "dominant has 10 ping"}, {"steamid": "[U:1:172044269]", "name": "eldoccc", "msg": "ye hefarms me"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "he needs at least 2 ping"}, {"steamid": "[U:1:204729823]", "name": "KoOoOOdEEeEeeY", "msg": "i had worse ping at lan"}, {"steamid": "[U:1:95820688]", "name": "Dominant", "msg": "6 is about the max"}, {"steamid": "[U:1:172044269]", "name": "eldoccc", "msg": "tfw when you happy with 60"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "rdy?"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "wadu hek?"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "*DEAD* Ignis_\u03c3\u03ba\u03b1\u03b8\u03ac\u03c1\u03b9 :  260 ping niger"}, {"steamid": "[U:1:204729823]", "name": "KoOoOOdEEeEeeY", "msg": "shotgun in 2018 smh"}, {"steamid": "[U:1:178869439]", "name": "herpestim", "msg": "alg?"}, {"steamid": "[U:1:81145222]", "name": "ash", "msg": "what"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "lucky med."}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "and scout"}, {"steamid": "[U:1:172044269]", "name": "eldoccc", "msg": "enough"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": "this is bullshit"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": "I did not hit her"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "UI WAS IN SPOAWN"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "shti banny bind"}, {"steamid": "[U:1:51723097]", "name": "sage LF demo 6s", "msg": "mode = in the zone (\u0e07\u0300-\u0301)\u0e07"}, {"steamid": "[U:1:59977210]", "name": "twiikuu | tf2.gg tf2pl.com", "msg": "WHAT THE FUCK"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "xd"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "zaid xD"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": ":__"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "haha"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": "mad arrows"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": ":))))))))))))))))))))"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": ":<"}, {"steamid": "[U:1:118758944]", "name": "Lava", "msg": "wadu hek?"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "ha"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "a7m"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "i had to 136 for him to force"}, {"steamid": "[U:1:111776267]", "name": "wanderlust_", "msg": "the balls on this guy"}, {"steamid": "[U:1:247875068]", "name": "Zaid", "msg": "xd"}, {"steamid": "[U:1:172534925]", "name": "_Sen", "msg": "nani"}, {"steamid": "[U:1:167517704]", "name": "Beelthazus", "msg": "000"}], "info": {"map": "cp_process_final", "supplemental": true, "total_length": 1756, "hasRealDamage": true, "hasWeaponDamage": true, "hasAccuracy": false, "hasHP": true, "hasHP_real": true, "hasHS": true, "hasHS_hit": true, "hasBS": false, "hasCP": true, "hasSB": false, "hasDT": true, "hasAS": true, "hasHR": true, "hasIntel": false, "AD_scoring": false, "notifications": [], "title": "serveme.tf #769415 - Trump vs RED", "date": 1521147164, "uploader": {"id": "76561197960497430", "name": "Arie - VanillaTF2.org", "info": "TFTrue v4.79"}}, "killstreaks": [{"steamid": "[U:1:59977210]", "streak": 3, "time": 20}, {"steamid": "[U:1:95820688]", "streak": 5, "time": 365}, {"steamid": "[U:1:81145222]", "streak": 3, "time": 572}, {"steamid": "[U:1:95820688]", "streak": 3, "time": 707}, {"steamid": "[U:1:95820688]", "streak": 3, "time": 1031}, {"steamid": "[U:1:95820688]", "streak": 3, "time": 1092}, {"steamid": "[U:1:118758944]", "streak": 3, "time": 1428}, {"steamid": "[U:1:172534925]", "streak": 3, "time": 1430}, {"steamid": "[U:1:204729823]", "streak": 3, "time": 1585}, {"steamid": "[U:1:95820688]", "streak": 3, "time": 1703}], "success": true}');

commit;
