-- Deploy fantasy_tf2:tournament to pg

begin;

    create table tournament
        ( slug text not null
        , name text not null
        , start_time timestamp not null
        , end_time timestamp
        , start_budget int not null
        , transactions int not null
        , primary key (slug)
        );

commit;
