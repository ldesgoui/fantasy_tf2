-- Deploy fantasy_tf2:match to pg

begin;

    create table match
        ( id serial not null
        , tournament text not null
        , description text
        , stage integer not null
        , primary key (id)
        , foreign key (tournament) references tournament
        );

commit;
