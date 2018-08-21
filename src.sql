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
        , start_budget          int not null
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
            new.total_score :=
                  new.game_win::int * 3
                + new.round_win * 3
                + new.frag
                + new.medic_frag
                + new.frag_as_medic * 2
                + new.dpm / 25
                + new.ubercharge * 2
                + new.ubercharge_dropped * -3
                + new.team_medic_death / -5
                + new.top_frag::int * 2
                + new.top_damage::int * 2
                + new.top_kdr::int * 2
                + new.airshot / 5
                + new.capture;
            return new;
        end;
    $$;

    create trigger performance_sum
        after insert or update on match_performance
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
                , to_timestamp(data->'info'->>'date')
                , data->'info'->>'title'
                )
            on conflict (id) do nothing;

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

                player := data->player_id;
                is_player_blue := player->>'team' == 'Blue';

                select d->'kills'
                  from jsonb_array_elements(player->'class_stats')
                 where d->>'type' == 'medic'
                  into frag_as_medic;

                if not exists then
                    frag_as_medic := 0;
                end if;

            -- TODO: player_id may cause this to fail in case it's a merc we don't know
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
                    , player->>'kills'
                    , coalesce(data->'classkills'->player_id->>'medic', 0)
                    , frag_as_medic
                    , coalesce(player->>'dapm', 0)
                    , coalesce(player->>'ubers', 0)
                    , coalesce(player->>'drops', 0)
                    , case when is_player_blue
                        then blue_team_medic_death
                        else red_team_medic_death
                    end
                    , top_fragger == player_id
                    , top_damager == player_id
                    , top_kdr == player_id
                    , coalesce(player->>'as', 0)
                    , coalesce(player->>'cpc', 0)
                    );

            end loop;

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

    create view active_contracts as
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
           from active_contracts
       group by (tournament, manager);

    create function create_transaction(tournament text, new_roster text[])
        returns bool
        language plpgsql
        strict
        security definer
        as $$
            declare
                m manager;
            begin

                select *
                  from manager
                 where steam_id = current_setting('request.jwt.claim.manager_id')
                  into m;

                return 'f';
                -- manager from auth
                -- new_roster size == 6
                -- new team_cost >= 0
                -- total transfers < max_transfers
                -- no more than 3 from same team
                -- 2 sct 2 sol 1 dem 1 med
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
        , '1'
        , 'kaidus'
        , 'Se7en'
        , 'demoman'
        , '1000'
        ),
        ( 'i63'
        , '2'
        , 'Thalash'
        , 'Se7en'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '3'
        , 'Thaigrr'
        , 'Se7en'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '4'
        , 'Adysky'
        , 'Se7en'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '5'
        , 'stark'
        , 'Se7en'
        , 'medic'
        , '1000'
        ),
        ( 'i63'
        , '6'
        , 'AMS'
        , 'Se7en'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '7'
        , 'shade'
        , 'froyotech'
        , 'medic'
        , '1000'
        ),
        ( 'i63'
        , '8'
        , 'b4nny'
        , 'froyotech'
        , 'scout'
        , '1000'
        ),
        ( 'i63'
        , '9'
        , 'blaze'
        , 'froyotech'
        , 'soldier'
        , '1000'
        ),
        ( 'i63'
        , '10'
        , 'habib'
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

commit;
