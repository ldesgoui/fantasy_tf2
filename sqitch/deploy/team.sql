-- Deploy fantasy_tf2:team to pg

begin;

    create table team
        ( tournament text not null
        , manager text not null
        , name text not null
        , start_budget int not null
        , primary key (tournament, manager)
        , foreign key (tournament) references tournament
        , foreign key (manager) references manager
        );

commit;
