-- Deploy fantasy_tf2:manager to pg

begin;

    create table manager
        ( steam_id text not null
        , name text not null
        , muted bool not null default false
        , admin bool not null default false
        , primary key (steam_id)
        );

commit;
