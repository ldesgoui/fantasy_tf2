-- Deploy fantasy_tf2:real_team to pg

begin;

    create table real_team
        ( tournament text not null
        , name text not null
        , primary key (tournament, name)
        , foreign key (tournament) references tournament
        );

commit;
