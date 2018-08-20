drop extension btree_gist cascade;
drop type class cascade;
drop table tournament cascade;
drop table team cascade;
drop table player cascade;
drop table manager cascade;
drop table fantasy_team cascade;
drop table contract cascade;
drop function create_transaction(text, text[]) cascade;
drop role anonymous;
drop role manager;
drop role admin;

begin;

    create extension btree_gist;

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

    -- TODO
    --create table match
    --    ( tournament            text not null references tournament
    --    , description           text
    --    , time                  timestamp
    --    , logs                  text[]
    --    );


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

    create view current_roster
        as select tournament, manager, player
             from contract
            where upper(time) is null;

    create view team_cost as
        select r.tournament
             , r.manager
             , sum(p.price) as team_cost
          from current_roster r
     left join player p on (r.tournament, r.player) = (p.tournament, p.steam_id)
      group by (r.tournament, r.manager);

    create function create_transaction(tournament text, new_roster text[])
        returns bool
        language plpgsql
        strict
        security definer
        as $$
            begin
                select 'f';
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
