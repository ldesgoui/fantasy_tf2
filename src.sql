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
        , total_score           int not null
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

    create function performance_sum()
        returns trigger
        language plpgsql
        as $$
        begin
            raise notice 'help';
            new.total_score :=
                  (new.game_win::int * 3)
                + (new.round_win * 3)
                + (new.frag)
                + (new.medic_frag)
                + (new.frag_as_medic * 2)
                + (new.dpm / 25)
                + (new.ubercharge * 2)
                + (new.ubercharge_dropped * -3)
                + (new.team_medic_death / -5)
                + (new.top_frag::int * 2)
                + (new.top_damage::int * 2)
                + (new.top_kdr::int * 2)
                + (new.airshot / 5)
                + (new.capture);
            return new;
        end;
    $$;

    create trigger performance_sum
        before insert or update on match_performance
        for each row execute procedure performance_sum();

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
          order by value->'kills'
             limit 1
              into top_fragger;

            select key
              from jsonb_each(data->'players')
          order by value->'dmg'
             limit 1
              into top_damager;

            select key
              from jsonb_each(data->'players')
          order by value->'kpd'
             limit 1
              into top_kdr;

            -- TODO
            blue_team_medic_death := 0;
            red_team_medic_death := 0;

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
                    , 0
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

    create function create_transaction(tournament text, new_roster text[])
        returns bool
        language plpgsql
        strict
        security definer
        as $$
            begin
                if not exists (
                        select steam_id
                          from manager
                         where steam_id = current_setting('request.jwt.claim.manager_id', true)
                    ) then
                    raise exception 'Manager does not exist';
                end if;

                if array_length(new_roster, 1) <> 6 then
                    raise exception 'New roster must be 6 players';
                end if;

                update contract
                   set time = tsrange(lower(time), now()::timestamp)
                 where contract.tournament = $1
                   and manager = current_setting('request.jwt.claim.manager_id', true)
                   and not (player = any (new_roster));

                if exists (
                    select 1
                      from team_transactions x
                 left join tournament t on x.tournament = t.name
                     where x.tournament = $1
                       and x.manager = manager
                       and x.team_transactions > t.transactions
                    ) then
                    raise exception 'Exceeded amount of transactions available';
                end if;

                if exists (
                    select 1
                      from team_cost x
                 left join tournament t on x.tournament = t.name
                     where x.tournament = $1
                       and x.manager = manager
                       and x.team_cost > t.budget
                    ) then
                    raise exception 'Exceeded budget spending';
                end if;

                -- TODO
                -- insert contracts
                -- no more than 3 from same team
                -- 2 sct 2 sol 1 dem 1 med

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
        , '[U:1:102433945]'
        , 'kaidus'
        , 'Se7en'
        , 'demoman'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:125148025]'
        , 'Thalash'
        , 'Se7en'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:142839983]'
        , 'Thaigrr'
        , 'Se7en'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:143476343]'
        , 'Adysky'
        , 'Se7en'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:148001982]'
        , 'stark'
        , 'Se7en'
        , 'medic'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:176526907]'
        , 'AMS'
        , 'Se7en'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:288207084]'
        , 'shade'
        , 'froyotech'
        , 'medic'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:327230505]'
        , 'b4nny'
        , 'froyotech'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:42659068]'
        , 'blaze'
        , 'froyotech'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:75261983]'
        , 'habib'
        , 'froyotech'
        , 'demoman'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:87325588]'
        , 'yomps'
        , 'froyotech'
        , 'demoman'
        , '1000'
        ),
        ( 'i63'
        , '[U:1:87741926]'
        , 'arekk'
        , 'froyotech'
        , 'demoman'
        , '1000'
        );

    insert into manager values
        ( '0'
        , 'twiikuu'
        );

    insert into fantasy_team values
        ( 'i63'
        , '0'
        , 'WARHURYEAH IS FOREVER'
        );

    select create_transaction('i63', '{1,2,3,7,8,9}');
    select import_logs('i63', '2099217', '{"version": 3, "teams": {"Red": {"score": 3, "kills": 103, "deaths": 0, "dmg": 35423, "charges": 10, "drops": 2, "firstcaps": 4, "caps": 18}, "Blue": {"score": 4, "kills": 102, "deaths": 0, "dmg": 37750, "charges": 8, "drops": 0, "firstcaps": 4, "caps": 21}}, "length": 1764, "players": {"[U:1:102433945]": {"team": "Red", "class_stats": [{"type": "medic", "kills": 1, "assists": 7, "deaths": 13, "dmg": 105, "weapon": {"crusaders_crossbow": {"kills": 0, "dmg": 40, "avg_dmg": 40, "shots": 100, "hits": 47}, "ubersaw": {"kills": 1, "dmg": 65, "avg_dmg": 65, "shots": 0, "hits": 0}}, "total_time": 1764}], "kills": 1, "deaths": 13, "assists": 7, "suicides": 0, "kapd": "0.6", "kpd": "0.1", "dmg": 105, "dmg_real": 61, "dt": 3775, "dt_real": 430, "hr": 0, "lks": 1, "as": 0, "dapd": 8, "dapm": 3, "ubers": 10, "ubertypes": {"medigun": 10}, "drops": 2, "medkits": 4, "medkits_hp": 111, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 29664, "cpc": 4, "ic": 0, "medicstats": {"deaths_with_95_99_uber": 0, "advantages_lost": 1, "biggest_advantage_lost": 16, "deaths_within_20s_after_uber": 2, "avg_time_before_healing": 5.39, "avg_time_to_build": 59.53846153846154, "avg_time_before_using": 15.7, "avg_uber_length": 6.659999999999999}}, "[U:1:148001982]": {"team": "Red", "class_stats": [{"type": "soldier", "kills": 21, "assists": 7, "deaths": 17, "dmg": 8902, "weapon": {"quake_rl": {"kills": 20, "dmg": 8902, "avg_dmg": 57.06410256410256, "shots": 357, "hits": 146}, "world": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1764}], "kills": 21, "deaths": 17, "assists": 7, "suicides": 0, "kapd": "1.6", "kpd": "1.2", "dmg": 8902, "dmg_real": 1034, "dt": 8531, "dt_real": 657, "hr": 10332, "lks": 5, "as": 3, "dapd": 523, "dapm": 302, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 26, "medkits_hp": 829, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 6, "ic": 0}, "[U:1:87741926]": {"team": "Blue", "class_stats": [{"type": "scout", "kills": 22, "assists": 13, "deaths": 18, "dmg": 6810, "weapon": {"the_winger": {"kills": 1, "dmg": 122, "avg_dmg": 11.090909090909092, "shots": 0, "hits": 0}, "scattergun": {"kills": 21, "dmg": 6688, "avg_dmg": 26.434782608695652, "shots": 349, "hits": 224}}, "total_time": 1496}, {"type": "sniper", "kills": 1, "assists": 0, "deaths": 2, "dmg": 935, "weapon": {"sniperrifle": {"kills": 1, "dmg": 935, "avg_dmg": 187, "shots": 14, "hits": 5}}, "total_time": 206}], "kills": 23, "deaths": 20, "assists": 13, "suicides": 0, "kapd": "1.8", "kpd": "1.1", "dmg": 7886, "dmg_real": 693, "dt": 6056, "dt_real": 709, "hr": 4623, "lks": 6, "as": 0, "dapd": 394, "dapm": 268, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 19, "medkits_hp": 425, "backstabs": 0, "headshots": 1, "headshots_hit": 2, "sentries": 0, "heal": 0, "cpc": 9, "ic": 0}, "[U:1:288207084]": {"team": "Blue", "class_stats": [{"type": "soldier", "kills": 9, "assists": 3, "deaths": 19, "dmg": 4173, "weapon": {"tf_projectile_rocket": {"kills": 9, "dmg": 4173, "avg_dmg": 54.1948051948052, "shots": 227, "hits": 72}}, "total_time": 1762}], "kills": 9, "deaths": 19, "assists": 3, "suicides": 0, "kapd": "0.6", "kpd": "0.5", "dmg": 4173, "dmg_real": 338, "dt": 6210, "dt_real": 913, "hr": 6545, "lks": 4, "as": 0, "dapd": 219, "dapm": 141, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 31, "medkits_hp": 1045, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 9, "ic": 0}, "[U:1:176526907]": {"team": "Red", "class_stats": [{"type": "demoman", "kills": 19, "assists": 5, "deaths": 20, "dmg": 7653, "weapon": {"tf_projectile_pipe": {"kills": 6, "dmg": 1986, "avg_dmg": 50.92307692307692, "shots": 134, "hits": 33}, "tf_projectile_pipe_remote": {"kills": 5, "dmg": 3375, "avg_dmg": 46.875, "shots": 296, "hits": 58}, "world": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}, "iron_bomber": {"kills": 7, "dmg": 2292, "avg_dmg": 61.945945945945944, "shots": 158, "hits": 35}}, "total_time": 1763}], "kills": 19, "deaths": 20, "assists": 5, "suicides": 0, "kapd": "1.2", "kpd": "0.9", "dmg": 7653, "dmg_real": 594, "dt": 7540, "dt_real": 658, "hr": 6412, "lks": 3, "as": 2, "dapd": 382, "dapm": 260, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 55, "medkits_hp": 1878, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 4, "ic": 0}, "[U:1:143476343]": {"team": "Blue", "class_stats": [{"type": "scout", "kills": 21, "assists": 11, "deaths": 13, "dmg": 6364, "weapon": {"scattergun": {"kills": 21, "dmg": 6356, "avg_dmg": 24.828125, "shots": 311, "hits": 224}, "pistol_scout": {"kills": 0, "dmg": 8, "avg_dmg": 8, "shots": 22, "hits": 1}}, "total_time": 1762}], "kills": 21, "deaths": 13, "assists": 11, "suicides": 0, "kapd": "2.5", "kpd": "1.6", "dmg": 6364, "dmg_real": 796, "dt": 5009, "dt_real": 525, "hr": 5116, "lks": 7, "as": 0, "dapd": 489, "dapm": 216, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 30, "medkits_hp": 740, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 15, "ic": 0}, "[U:1:75261983]": {"team": "Red", "class_stats": [{"type": "soldier", "kills": 22, "assists": 7, "deaths": 24, "dmg": 7830, "weapon": {"tf_projectile_rocket": {"kills": 21, "dmg": 7765, "avg_dmg": 62.12, "shots": 270, "hits": 115}, "unique_pickaxe_escape": {"kills": 1, "dmg": 65, "avg_dmg": 65, "shots": 0, "hits": 0}}, "total_time": 1762}], "kills": 22, "deaths": 24, "assists": 7, "suicides": 0, "kapd": "1.2", "kpd": "0.9", "dmg": 7830, "dmg_real": 1064, "dt": 6931, "dt_real": 1018, "hr": 2398, "lks": 4, "as": 0, "dapd": 326, "dapm": 266, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 65, "medkits_hp": 2127, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 5, "ic": 0}, "[U:1:42659068]": {"team": "Blue", "class_stats": [{"type": "soldier", "kills": 21, "assists": 2, "deaths": 25, "dmg": 8331, "weapon": {"quake_rl": {"kills": 20, "dmg": 8331, "avg_dmg": 54.450980392156865, "shots": 317, "hits": 130}, "world": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1763}], "kills": 21, "deaths": 25, "assists": 2, "suicides": 0, "kapd": "0.9", "kpd": "0.8", "dmg": 8331, "dmg_real": 1000, "dt": 6484, "dt_real": 881, "hr": 2649, "lks": 2, "as": 0, "dapd": 333, "dapm": 283, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 74, "medkits_hp": 2454, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 1, "ic": 0}, "[U:1:327230505]": {"team": "Blue", "class_stats": [{"type": "medic", "kills": 0, "assists": 14, "deaths": 13, "dmg": 331, "weapon": {"crusaders_crossbow": {"kills": 0, "dmg": 331, "avg_dmg": 55.166666666666664, "shots": 112, "hits": 50}, "syringegun_medic": {"kills": 0, "dmg": 0, "avg_dmg": 0, "shots": 2, "hits": 0}}, "total_time": 1764}], "kills": 0, "deaths": 13, "assists": 14, "suicides": 0, "kapd": "1.1", "kpd": "0.0", "dmg": 331, "dmg_real": 0, "dt": 3486, "dt_real": 418, "hr": 0, "lks": 0, "as": 0, "dapd": 25, "dapm": 11, "ubers": 8, "ubertypes": {"medigun": 8}, "drops": 0, "medkits": 5, "medkits_hp": 176, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 26951, "cpc": 8, "ic": 0, "medicstats": {"advantages_lost": 2, "biggest_advantage_lost": 28, "deaths_with_95_99_uber": 0, "deaths_within_20s_after_uber": 1, "avg_time_before_healing": 5.938461538461539, "avg_time_to_build": 66.55555555555556, "avg_time_before_using": 34.375, "avg_uber_length": 6.324999999999999}}, "[U:1:125148025]": {"team": "Red", "class_stats": [{"type": "scout", "kills": 16, "assists": 11, "deaths": 11, "dmg": 4449, "weapon": {"pistol_scout": {"kills": 1, "dmg": 271, "avg_dmg": 14.263157894736842, "shots": 129, "hits": 19}, "scattergun": {"kills": 14, "dmg": 4178, "avg_dmg": 18.486725663716815, "shots": 353, "hits": 206}, "world": {"kills": 1, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1696}, {"type": "pyro", "kills": 0, "assists": 0, "deaths": 1, "dmg": 144, "weapon": {"flamethrower": {"kills": 0, "dmg": 49, "avg_dmg": 2.7222222222222223, "shots": 0, "hits": 0}, "tf_projectile_pipe": {"kills": 0, "dmg": 95, "avg_dmg": 47.5, "shots": 0, "hits": 0}}, "total_time": 27}], "kills": 16, "deaths": 12, "assists": 11, "suicides": 0, "kapd": "2.3", "kpd": "1.3", "dmg": 4647, "dmg_real": 450, "dt": 5169, "dt_real": 474, "hr": 6560, "lks": 5, "as": 0, "dapd": 387, "dapm": 158, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 24, "medkits_hp": 654, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 13, "ic": 0}, "[U:1:142839983]": {"team": "Red", "class_stats": [{"type": "scout", "kills": 22, "assists": 14, "deaths": 14, "dmg": 5878, "weapon": {"scattergun": {"kills": 22, "dmg": 5862, "avg_dmg": 26.286995515695068, "shots": 311, "hits": 211}, "pistol_scout": {"kills": 0, "dmg": 16, "avg_dmg": 8, "shots": 9, "hits": 2}}, "total_time": 1557}, {"type": "pyro", "kills": 1, "assists": 1, "deaths": 1, "dmg": 93, "weapon": {"shotgun_pyro": {"kills": 0, "dmg": 40, "avg_dmg": 10, "shots": 7, "hits": 4}, "flamethrower": {"kills": 1, "dmg": 53, "avg_dmg": 7.571428571428571, "shots": 0, "hits": 0}}, "total_time": 138}, {"type": "sniper", "kills": 1, "assists": 0, "deaths": 1, "dmg": 315, "weapon": {"awper_hand": {"kills": 1, "dmg": 315, "avg_dmg": 315, "shots": 3, "hits": 1}}, "total_time": 66}], "kills": 24, "deaths": 16, "assists": 15, "suicides": 0, "kapd": "2.4", "kpd": "1.5", "dmg": 6286, "dmg_real": 730, "dt": 5804, "dt_real": 553, "hr": 3962, "lks": 4, "as": 0, "dapd": 392, "dapm": 213, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 21, "medkits_hp": 564, "backstabs": 0, "headshots": 1, "headshots_hit": 1, "sentries": 0, "heal": 0, "cpc": 9, "ic": 0}, "[U:1:87325588]": {"team": "Blue", "class_stats": [{"type": "demoman", "kills": 28, "assists": 9, "deaths": 13, "dmg": 10665, "weapon": {"tf_projectile_pipe_remote": {"kills": 15, "dmg": 7550, "avg_dmg": 50, "shots": 450, "hits": 132}, "iron_bomber": {"kills": 11, "dmg": 3115, "avg_dmg": 70.79545454545455, "shots": 157, "hits": 41}, "world": {"kills": 2, "dmg": 0, "avg_dmg": 0, "shots": 0, "hits": 0}}, "total_time": 1764}], "kills": 28, "deaths": 13, "assists": 9, "suicides": 0, "kapd": "2.8", "kpd": "2.2", "dmg": 10665, "dmg_real": 963, "dt": 8178, "dt_real": 487, "hr": 8018, "lks": 7, "as": 2, "dapd": 820, "dapm": 362, "ubers": 0, "ubertypes": {}, "drops": 0, "medkits": 45, "medkits_hp": 1677, "backstabs": 0, "headshots": 0, "headshots_hit": 0, "sentries": 0, "heal": 0, "cpc": 9, "ic": 0}}, "names": {"[U:1:102433945]": "Ghost", "[U:1:148001982]": "lexx", "[U:1:87741926]": "iven \ud83e\udd20", "[U:1:288207084]": "bub", "[U:1:176526907]": "shupah", "[U:1:143476343]": "cold light of day", "[U:1:75261983]": "Dave", "[U:1:42659068]": "Bunneez", "[U:1:327230505]": "undrex \u03b5\u0457\u0437", "[U:1:125148025]": "samson", "[U:1:142839983]": "\u2665", "[U:1:87325588]": "susurrus"}, "rounds": [{"start_time": 1534859221, "winner": "Blue", "team": {"Blue": {"score": 1, "kills": 16, "dmg": 4800, "ubers": 2}, "Red": {"score": 0, "kills": 8, "dmg": 2847, "ubers": 1}}, "events": [{"type": "medic_death", "time": 23, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:42659068]"}, {"type": "pointcap", "time": 56, "team": "Red", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 76, "steamid": "[U:1:327230505]", "team": "Blue"}, {"type": "pointcap", "time": 99, "team": "Blue", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 113, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "pointcap", "time": 148, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 151, "steamid": "[U:1:327230505]", "team": "Blue"}, {"type": "medic_death", "time": 157, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:87325588]"}, {"type": "pointcap", "time": 165, "team": "Blue", "point": 5}, {"type": "round_win", "time": 165, "team": "Blue"}], "players": {"[U:1:87325588]": {"team": "Blue", "kills": 7, "dmg": 1825}, "[U:1:87741926]": {"team": "Blue", "kills": 3, "dmg": 1178}, "[U:1:143476343]": {"team": "Blue", "kills": 2, "dmg": 656}, "[U:1:75261983]": {"team": "Red", "kills": 1, "dmg": 737}, "[U:1:142839983]": {"team": "Red", "kills": 2, "dmg": 332}, "[U:1:125148025]": {"team": "Red", "kills": 1, "dmg": 309}, "[U:1:148001982]": {"team": "Red", "kills": 1, "dmg": 781}, "[U:1:42659068]": {"team": "Blue", "kills": 3, "dmg": 857}, "[U:1:288207084]": {"team": "Blue", "kills": 1, "dmg": 284}, "[U:1:176526907]": {"team": "Red", "kills": 3, "dmg": 688}, "[U:1:102433945]": {"team": "Red", "kills": 0, "dmg": 0}, "[U:1:327230505]": {"team": "Blue", "kills": 0, "dmg": 0}, "[U:1:126485428]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:66381839]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:83940329]": {"team": null, "kills": 0, "dmg": 0}}, "firstcap": "Red", "length": 165}, {"start_time": 1534859392, "winner": "Red", "team": {"Blue": {"score": 1, "kills": 1, "dmg": 1543, "ubers": 0}, "Red": {"score": 1, "kills": 8, "dmg": 2105, "ubers": 1}}, "events": [{"type": "medic_death", "time": 208, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:142839983]"}, {"type": "pointcap", "time": 228, "team": "Red", "point": 3}, {"type": "pointcap", "time": 241, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 250, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "pointcap", "time": 260, "team": "Red", "point": 1}, {"type": "round_win", "time": 260, "team": "Red"}], "players": {"[U:1:87325588]": {"team": "Blue", "kills": 0, "dmg": 421}, "[U:1:176526907]": {"team": "Red", "kills": 2, "dmg": 375}, "[U:1:142839983]": {"team": "Red", "kills": 1, "dmg": 356}, "[U:1:143476343]": {"team": "Blue", "kills": 0, "dmg": 371}, "[U:1:87741926]": {"team": "Blue", "kills": 0, "dmg": 209}, "[U:1:42659068]": {"team": "Blue", "kills": 1, "dmg": 282}, "[U:1:148001982]": {"team": "Red", "kills": 3, "dmg": 614}, "[U:1:75261983]": {"team": "Red", "kills": 1, "dmg": 562}, "[U:1:125148025]": {"team": "Red", "kills": 1, "dmg": 198}, "[U:1:327230505]": {"team": "Blue", "kills": 0, "dmg": 92}, "[U:1:288207084]": {"team": "Blue", "kills": 0, "dmg": 168}, "[U:1:102433945]": {"team": "Red", "kills": 0, "dmg": 0}, "[U:1:126485428]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:66381839]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:83940329]": {"team": null, "kills": 0, "dmg": 0}}, "firstcap": "Red", "length": 89}, {"start_time": 1534859486, "winner": "Red", "team": {"Blue": {"score": 1, "kills": 2, "dmg": 2036, "ubers": 0}, "Red": {"score": 2, "kills": 6, "dmg": 2616, "ubers": 1}}, "events": [{"type": "medic_death", "time": 288, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:142839983]"}, {"type": "pointcap", "time": 324, "team": "Red", "point": 3}, {"type": "pointcap", "time": 333, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 349, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "pointcap", "time": 358, "team": "Red", "point": 1}, {"type": "round_win", "time": 358, "team": "Red"}], "players": {"[U:1:176526907]": {"team": "Red", "kills": 0, "dmg": 423}, "[U:1:87325588]": {"team": "Blue", "kills": 1, "dmg": 466}, "[U:1:142839983]": {"team": "Red", "kills": 2, "dmg": 642}, "[U:1:143476343]": {"team": "Blue", "kills": 1, "dmg": 182}, "[U:1:125148025]": {"team": "Red", "kills": 1, "dmg": 560}, "[U:1:87741926]": {"team": "Blue", "kills": 0, "dmg": 331}, "[U:1:327230505]": {"team": "Blue", "kills": 0, "dmg": 70}, "[U:1:42659068]": {"team": "Blue", "kills": 0, "dmg": 691}, "[U:1:288207084]": {"team": "Blue", "kills": 0, "dmg": 296}, "[U:1:75261983]": {"team": "Red", "kills": 1, "dmg": 313}, "[U:1:148001982]": {"team": "Red", "kills": 2, "dmg": 678}, "[U:1:102433945]": {"team": "Red", "kills": 0, "dmg": 0}, "[U:1:126485428]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:66381839]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:83940329]": {"team": null, "kills": 0, "dmg": 0}}, "firstcap": "Red", "length": 93}, {"start_time": 1534859584, "winner": "Blue", "team": {"Blue": {"score": 2, "kills": 14, "dmg": 3511, "ubers": 0}, "Red": {"score": 2, "kills": 4, "dmg": 1610, "ubers": 0}}, "events": [{"type": "medic_death", "time": 381, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:176526907]"}, {"type": "medic_death", "time": 389, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:42659068]"}, {"type": "pointcap", "time": 410, "team": "Blue", "point": 3}, {"type": "medic_death", "time": 433, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:148001982]"}, {"type": "pointcap", "time": 435, "team": "Blue", "point": 4}, {"type": "drop", "time": 473, "team": "Red", "steamid": "[U:1:102433945]"}, {"type": "medic_death", "time": 473, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:143476343]"}, {"type": "pointcap", "time": 484, "team": "Blue", "point": 5}, {"type": "round_win", "time": 484, "team": "Blue"}], "players": {"[U:1:87325588]": {"team": "Blue", "kills": 4, "dmg": 1220}, "[U:1:176526907]": {"team": "Red", "kills": 1, "dmg": 691}, "[U:1:143476343]": {"team": "Blue", "kills": 5, "dmg": 864}, "[U:1:87741926]": {"team": "Blue", "kills": 2, "dmg": 680}, "[U:1:142839983]": {"team": "Red", "kills": 1, "dmg": 206}, "[U:1:148001982]": {"team": "Red", "kills": 1, "dmg": 400}, "[U:1:42659068]": {"team": "Blue", "kills": 2, "dmg": 613}, "[U:1:75261983]": {"team": "Red", "kills": 1, "dmg": 240}, "[U:1:125148025]": {"team": "Red", "kills": 0, "dmg": 73}, "[U:1:288207084]": {"team": "Blue", "kills": 1, "dmg": 134}, "[U:1:102433945]": {"team": "Red", "kills": 0, "dmg": 0}, "[U:1:327230505]": {"team": "Blue", "kills": 0, "dmg": 0}, "[U:1:126485428]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:66381839]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:83940329]": {"team": null, "kills": 0, "dmg": 0}}, "firstcap": "Blue", "length": 121}, {"start_time": 1534859710, "winner": "Red", "team": {"Blue": {"score": 2, "kills": 20, "dmg": 8514, "ubers": 2}, "Red": {"score": 3, "kills": 27, "dmg": 9157, "ubers": 3}}, "events": [{"type": "pointcap", "time": 539, "team": "Red", "point": 3}, {"type": "pointcap", "time": 558, "team": "Red", "point": 2}, {"type": "pointcap", "time": 579, "team": "Blue", "point": 2}, {"type": "pointcap", "time": 599, "team": "Blue", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 611, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "charge", "medigun": "medigun", "time": 612, "steamid": "[U:1:327230505]", "team": "Blue"}, {"type": "medic_death", "time": 620, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:142839983]"}, {"type": "pointcap", "time": 643, "team": "Red", "point": 3}, {"type": "medic_death", "time": 662, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:148001982]"}, {"type": "medic_death", "time": 686, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:87741926]"}, {"type": "medic_death", "time": 710, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:75261983]"}, {"type": "pointcap", "time": 714, "team": "Blue", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 759, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "pointcap", "time": 776, "team": "Red", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 823, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "charge", "medigun": "medigun", "time": 823, "steamid": "[U:1:327230505]", "team": "Blue"}, {"type": "medic_death", "time": 860, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:142839983]"}, {"type": "medic_death", "time": 865, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:87325588]"}, {"type": "pointcap", "time": 881, "team": "Red", "point": 2}, {"type": "medic_death", "time": 900, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:42659068]"}, {"type": "pointcap", "time": 904, "team": "Red", "point": 1}, {"type": "round_win", "time": 904, "team": "Red"}], "players": {"[U:1:87325588]": {"team": "Blue", "kills": 5, "dmg": 2656}, "[U:1:143476343]": {"team": "Blue", "kills": 0, "dmg": 1161}, "[U:1:87741926]": {"team": "Blue", "kills": 8, "dmg": 1989}, "[U:1:142839983]": {"team": "Red", "kills": 6, "dmg": 1249}, "[U:1:125148025]": {"team": "Red", "kills": 3, "dmg": 1258}, "[U:1:75261983]": {"team": "Red", "kills": 7, "dmg": 1942}, "[U:1:148001982]": {"team": "Red", "kills": 9, "dmg": 3214}, "[U:1:42659068]": {"team": "Blue", "kills": 4, "dmg": 1688}, "[U:1:288207084]": {"team": "Blue", "kills": 3, "dmg": 1020}, "[U:1:176526907]": {"team": "Red", "kills": 2, "dmg": 1454}, "[U:1:102433945]": {"team": "Red", "kills": 0, "dmg": 40}, "[U:1:327230505]": {"team": "Blue", "kills": 0, "dmg": 0}, "[U:1:126485428]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:66381839]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:83940329]": {"team": null, "kills": 0, "dmg": 0}}, "firstcap": "Red", "length": 415}, {"start_time": 1534860130, "winner": "Blue", "team": {"Blue": {"score": 3, "kills": 35, "dmg": 12861, "ubers": 4}, "Red": {"score": 3, "kills": 38, "dmg": 13395, "ubers": 4}}, "events": [{"type": "medic_death", "time": 935, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:42659068]"}, {"type": "pointcap", "time": 951, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 967, "team": "Blue", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 980, "steamid": "[U:1:327230505]", "team": "Blue"}, {"type": "pointcap", "time": 1018, "team": "Red", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 1035, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "pointcap", "time": 1054, "team": "Red", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 1057, "steamid": "[U:1:327230505]", "team": "Blue"}, {"type": "pointcap", "time": 1074, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 1089, "team": "Blue", "point": 4}, {"type": "drop", "time": 1243, "team": "Red", "steamid": "[U:1:102433945]"}, {"type": "medic_death", "time": 1243, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:42659068]"}, {"type": "charge", "medigun": "medigun", "time": 1248, "steamid": "[U:1:327230505]", "team": "Blue"}, {"type": "medic_death", "time": 1270, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:142839983]"}, {"type": "pointcap", "time": 1292, "team": "Red", "point": 4}, {"type": "charge", "medigun": "medigun", "time": 1326, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "medic_death", "time": 1334, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:102433945]"}, {"type": "pointcap", "time": 1354, "team": "Red", "point": 3}, {"type": "pointcap", "time": 1363, "team": "Red", "point": 2}, {"type": "charge", "medigun": "medigun", "time": 1381, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "medic_death", "time": 1389, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:143476343]"}, {"type": "pointcap", "time": 1414, "team": "Blue", "point": 2}, {"type": "pointcap", "time": 1454, "team": "Blue", "point": 3}, {"type": "charge", "medigun": "medigun", "time": 1484, "steamid": "[U:1:327230505]", "team": "Blue"}, {"type": "charge", "medigun": "medigun", "time": 1485, "steamid": "[U:1:102433945]", "team": "Red"}, {"type": "medic_death", "time": 1494, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:42659068]"}, {"type": "medic_death", "time": 1504, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:142839983]"}, {"type": "pointcap", "time": 1534, "team": "Blue", "point": 4}, {"type": "pointcap", "time": 1608, "team": "Blue", "point": 5}, {"type": "round_win", "time": 1608, "team": "Blue"}], "players": {"[U:1:143476343]": {"team": "Blue", "kills": 8, "dmg": 2158}, "[U:1:87325588]": {"team": "Blue", "kills": 8, "dmg": 2739}, "[U:1:125148025]": {"team": "Red", "kills": 6, "dmg": 1714}, "[U:1:87741926]": {"team": "Blue", "kills": 7, "dmg": 2646}, "[U:1:142839983]": {"team": "Red", "kills": 9, "dmg": 2516}, "[U:1:176526907]": {"team": "Red", "kills": 9, "dmg": 3098}, "[U:1:288207084]": {"team": "Blue", "kills": 4, "dmg": 1791}, "[U:1:42659068]": {"team": "Blue", "kills": 8, "dmg": 3400}, "[U:1:75261983]": {"team": "Red", "kills": 10, "dmg": 3434}, "[U:1:148001982]": {"team": "Red", "kills": 3, "dmg": 2568}, "[U:1:327230505]": {"team": "Blue", "kills": 0, "dmg": 127}, "[U:1:102433945]": {"team": "Red", "kills": 1, "dmg": 65}, "[U:1:126485428]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:66381839]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:83940329]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:226503822]": {"team": null, "kills": 0, "dmg": 0}}, "firstcap": "Blue", "length": 699}, {"start_time": 1534860834, "winner": "Blue", "team": {"Blue": {"score": 4, "kills": 6, "dmg": 1973, "ubers": 0}, "Red": {"score": 3, "kills": 3, "dmg": 1257, "ubers": 0}}, "events": [{"type": "medic_death", "time": 1638, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:42659068]"}, {"type": "medic_death", "time": 1650, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:148001982]"}, {"type": "pointcap", "time": 1669, "team": "Blue", "point": 3}, {"type": "pointcap", "time": 1683, "team": "Blue", "point": 4}, {"type": "pointcap", "time": 1707, "team": "Blue", "point": 5}, {"type": "round_win", "time": 1707, "team": "Blue"}], "players": {"[U:1:87325588]": {"team": "Blue", "kills": 1, "dmg": 570}, "[U:1:142839983]": {"team": "Red", "kills": 2, "dmg": 461}, "[U:1:143476343]": {"team": "Blue", "kills": 3, "dmg": 478}, "[U:1:87741926]": {"team": "Blue", "kills": 1, "dmg": 421}, "[U:1:42659068]": {"team": "Blue", "kills": 1, "dmg": 398}, "[U:1:125148025]": {"team": "Red", "kills": 0, "dmg": 95}, "[U:1:288207084]": {"team": "Blue", "kills": 0, "dmg": 106}, "[U:1:176526907]": {"team": "Red", "kills": 0, "dmg": 187}, "[U:1:148001982]": {"team": "Red", "kills": 1, "dmg": 276}, "[U:1:75261983]": {"team": "Red", "kills": 0, "dmg": 238}, "[U:1:102433945]": {"team": "Red", "kills": 0, "dmg": 0}, "[U:1:327230505]": {"team": "Blue", "kills": 0, "dmg": 0}, "[U:1:126485428]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:66381839]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:83940329]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:226503822]": {"team": null, "kills": 0, "dmg": 0}}, "firstcap": "Blue", "length": 94}, {"start_time": 1534860933, "winner": "Blue", "team": {"Blue": {"score": 4, "kills": 8, "dmg": 2512, "ubers": 0}, "Red": {"score": 3, "kills": 9, "dmg": 2436, "ubers": 0}}, "events": [{"type": "medic_death", "time": 1738, "team": "Red", "steamid": "[U:1:102433945]", "killer": "[U:1:42659068]"}, {"type": "medic_death", "time": 1744, "team": "Blue", "steamid": "[U:1:327230505]", "killer": "[U:1:142839983]"}, {"type": "pointcap", "time": 1773, "team": "Blue", "point": 3}, {"type": "round_win", "time": 1800, "team": "Blue"}], "players": {"[U:1:176526907]": {"team": "Red", "kills": 2, "dmg": 737}, "[U:1:143476343]": {"team": "Blue", "kills": 2, "dmg": 494}, "[U:1:142839983]": {"team": "Red", "kills": 1, "dmg": 524}, "[U:1:87741926]": {"team": "Blue", "kills": 2, "dmg": 432}, "[U:1:75261983]": {"team": "Red", "kills": 1, "dmg": 364}, "[U:1:148001982]": {"team": "Red", "kills": 1, "dmg": 371}, "[U:1:87325588]": {"team": "Blue", "kills": 2, "dmg": 768}, "[U:1:125148025]": {"team": "Red", "kills": 4, "dmg": 440}, "[U:1:42659068]": {"team": "Blue", "kills": 2, "dmg": 402}, "[U:1:288207084]": {"team": "Blue", "kills": 0, "dmg": 374}, "[U:1:327230505]": {"team": "Blue", "kills": 0, "dmg": 42}, "[U:1:102433945]": {"team": "Red", "kills": 0, "dmg": 0}, "[U:1:126485428]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:66381839]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:83940329]": {"team": null, "kills": 0, "dmg": 0}, "[U:1:226503822]": {"team": null, "kills": 0, "dmg": 0}}, "firstcap": "Blue", "length": 88}], "healspread": {"[U:1:102433945]": {"[U:1:176526907]": 6412, "[U:1:75261983]": 2398, "[U:1:125148025]": 6560, "[U:1:142839983]": 3962, "[U:1:148001982]": 10332}, "[U:1:327230505]": {"[U:1:87325588]": 8018, "[U:1:42659068]": 2649, "[U:1:87741926]": 4623, "[U:1:288207084]": 6545, "[U:1:143476343]": 5116}}, "classkills": {"[U:1:42659068]": {"medic": 8, "soldier": 7, "demoman": 2, "scout": 4}, "[U:1:176526907]": {"demoman": 4, "scout": 6, "soldier": 7, "medic": 1, "sniper": 1}, "[U:1:288207084]": {"soldier": 3, "demoman": 4, "scout": 2}, "[U:1:142839983]": {"soldier": 7, "scout": 7, "medic": 7, "demoman": 3}, "[U:1:87741926]": {"scout": 9, "soldier": 6, "demoman": 5, "sniper": 1, "medic": 1, "pyro": 1}, "[U:1:125148025]": {"scout": 7, "soldier": 9}, "[U:1:87325588]": {"demoman": 5, "soldier": 16, "scout": 5, "medic": 2}, "[U:1:143476343]": {"pyro": 1, "soldier": 9, "demoman": 4, "medic": 2, "scout": 5}, "[U:1:75261983]": {"soldier": 11, "scout": 7, "medic": 1, "sniper": 1, "demoman": 2}, "[U:1:148001982]": {"soldier": 10, "medic": 3, "demoman": 4, "scout": 4}, "[U:1:102433945]": {"medic": 1}}, "classdeaths": {"[U:1:102433945]": {"soldier": 8, "demoman": 2, "scout": 3}, "[U:1:87325588]": {"demoman": 4, "soldier": 6, "scout": 2, "sniper": 1}, "[U:1:143476343]": {"demoman": 4, "soldier": 3, "scout": 5, "pyro": 1}, "[U:1:75261983]": {"soldier": 6, "scout": 13, "demoman": 5}, "[U:1:42659068]": {"scout": 10, "soldier": 10, "demoman": 5}, "[U:1:148001982]": {"soldier": 4, "demoman": 11, "scout": 2}, "[U:1:142839983]": {"scout": 9, "demoman": 4, "soldier": 2, "sniper": 1}, "[U:1:87741926]": {"scout": 8, "soldier": 9, "demoman": 3}, "[U:1:176526907]": {"demoman": 5, "scout": 9, "soldier": 6}, "[U:1:125148025]": {"scout": 7, "soldier": 4, "demoman": 1}, "[U:1:288207084]": {"soldier": 11, "demoman": 2, "scout": 6}, "[U:1:327230505]": {"scout": 7, "demoman": 1, "soldier": 4, "medic": 1}}, "classkillassists": {"[U:1:42659068]": {"medic": 8, "soldier": 7, "scout": 5, "demoman": 3}, "[U:1:176526907]": {"demoman": 5, "scout": 7, "soldier": 8, "medic": 3, "sniper": 1}, "[U:1:75261983]": {"demoman": 4, "soldier": 12, "scout": 10, "medic": 1, "sniper": 2}, "[U:1:288207084]": {"soldier": 3, "demoman": 4, "scout": 4, "medic": 1}, "[U:1:143476343]": {"soldier": 13, "demoman": 9, "pyro": 1, "medic": 2, "scout": 7}, "[U:1:142839983]": {"soldier": 12, "scout": 13, "medic": 8, "demoman": 6}, "[U:1:148001982]": {"soldier": 13, "scout": 8, "medic": 3, "demoman": 4}, "[U:1:87741926]": {"scout": 13, "demoman": 6, "soldier": 13, "sniper": 1, "medic": 2, "pyro": 1}, "[U:1:125148025]": {"scout": 8, "medic": 1, "soldier": 17, "demoman": 1}, "[U:1:87325588]": {"demoman": 7, "soldier": 18, "scout": 6, "medic": 5, "pyro": 1}, "[U:1:327230505]": {"soldier": 8, "demoman": 2, "scout": 4}, "[U:1:102433945]": {"soldier": 5, "scout": 1, "demoman": 1, "medic": 1}}, "chat": [{"steamid": "[U:1:87325588]", "name": "susurrus", "msg": "wtGF"}, {"steamid": "[U:1:66381839]", "name": "dogroll", "msg": "https://www.youtube.com/watch?v=5nRdrum6iQI"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "fkn lex"}, {"steamid": "[U:1:288207084]", "name": "bub", "msg": " ?"}, {"steamid": "[U:1:148001982]", "name": "lexx", "msg": "who"}, {"steamid": "[U:1:87325588]", "name": "susurrus", "msg": "dave why do ujust waddle under shooting directs u big noob"}, {"steamid": "[U:1:42659068]", "name": "Bunneez", "msg": "i see shupah"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "full uber ad"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "goes river"}, {"steamid": "[U:1:42659068]", "name": "Bunneez", "msg": ">:)"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "i got dogged"}, {"steamid": "[U:1:87325588]", "name": "susurrus", "msg": "+u suck dave"}, {"steamid": "[U:1:66381839]", "name": "dogroll", "msg": "samson scout exists?"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "can u shoot the point??"}, {"steamid": "[U:1:125148025]", "name": "samson", "msg": "rofl"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "how do we lose"}, {"steamid": "[U:1:102433945]", "name": "Ghost", "msg": "idk"}, {"steamid": "[U:1:142839983]", "name": "\u2665", "msg": "i dont get healed u noob"}, {"steamid": "[U:1:66381839]", "name": "dogroll", "msg": "susurrus didnt miss a stick all mid"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "yup"}, {"steamid": "[U:1:66381839]", "name": "dogroll", "msg": ".ss"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "iven sucks"}, {"steamid": "[U:1:42659068]", "name": "Bunneez", "msg": "HE CALLED U"}, {"steamid": "[U:1:87325588]", "name": "susurrus", "msg": "?"}, {"steamid": "[U:1:125148025]", "name": "samson", "msg": "lol"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "?>"}, {"steamid": "[U:1:288207084]", "name": "bub", "msg": "how did our med live"}, {"steamid": "[U:1:288207084]", "name": "bub", "msg": "nice"}, {"steamid": "[U:1:42659068]", "name": "Bunneez", "msg": "hey"}, {"steamid": "[U:1:42659068]", "name": "Bunneez", "msg": "no swiping"}, {"steamid": "[U:1:66381839]", "name": "dogroll", "msg": ".ss"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "iven sucks"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "NOOOOO"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "???"}, {"steamid": "[U:1:87325588]", "name": "susurrus", "msg": "ROFL"}, {"steamid": "[U:1:288207084]", "name": "bub", "msg": "legend"}, {"steamid": "[U:1:87325588]", "name": "susurrus", "msg": "?"}, {"steamid": "[U:1:87741926]", "name": "iven \ud83e\udd20", "msg": "nice dave"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "iven sucks"}, {"steamid": "[U:1:42659068]", "name": "Bunneez", "msg": "frag em "}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "yeeeep"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "iven sucks"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "do we have ad"}, {"steamid": "[U:1:87741926]", "name": "iven \ud83e\udd20", "msg": "u did"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "why didnt u tell me??"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "woops"}, {"steamid": "[U:1:42659068]", "name": "Bunneez", "msg": "billy"}, {"steamid": "[U:1:66381839]", "name": "dogroll", "msg": "what lagswitch you using shupah"}, {"steamid": "[U:1:176526907]", "name": "shupah", "msg": "a sister"}, {"steamid": "[U:1:288207084]", "name": "bub", "msg": "ez dubz"}, {"steamid": "[U:1:87325588]", "name": "susurrus", "msg": "nice bait dave"}, {"steamid": "[U:1:75261983]", "name": "Dave", "msg": "where u???"}, {"steamid": "[U:1:87325588]", "name": "susurrus", "msg": "dead already??"}, {"steamid": "[U:1:288207084]", "name": "bub", "msg": "WTF"}, {"steamid": "[U:1:66381839]", "name": "dogroll", "msg": ".ss"}], "info": {"map": "cp_gullywash_final1", "supplemental": true, "total_length": 1764, "hasRealDamage": true, "hasWeaponDamage": true, "hasAccuracy": true, "hasHP": true, "hasHP_real": true, "hasHS": true, "hasHS_hit": true, "hasBS": false, "hasCP": true, "hasSB": false, "hasDT": true, "hasAS": true, "hasHR": true, "hasIntel": false, "AD_scoring": false, "notifications": [], "title": "ozfortress.com 1: RED vs BLU", "date": 1534832232, "uploader": {"id": "76561198061469495", "name": "obla", "info": "LogsTF 2.3.0"}}, "killstreaks": [{"steamid": "[U:1:87325588]", "streak": 3, "time": 157}, {"steamid": "[U:1:87741926]", "streak": 3, "time": 676}, {"steamid": "[U:1:142839983]", "streak": 3, "time": 860}, {"steamid": "[U:1:143476343]", "streak": 3, "time": 468}, {"steamid": "[U:1:176526907]", "streak": 3, "time": 987}], "success": true}');

commit;
