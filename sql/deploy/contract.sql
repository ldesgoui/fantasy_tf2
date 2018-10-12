-- Deploy fantasy_tf2:contract to pg

begin;

    create table contract
        ( id serial not null
        , tournament text not null
        , manager text not null
        , player text not null
        , time tsrange not null
        , purchase_price int not null
        , sale_price int
        , exclude using gist
            ( tournament with =
            , manager with =
            , player with =
            , time with &&
            )
        , primary key (id)
        , foreign key (tournament) references tournament
        , foreign key (manager) references manager
        , foreign key (tournament, manager) references team
        , foreign key (tournament, player) references player
        );

    create index on contract (tournament, manager);

commit;
