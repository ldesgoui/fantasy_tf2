-- Deploy fantasy_tf2:performance to pg

begin;

    create table performance
        ( map text not null
        , tournament text not null
        , player text not null
        , statistic text not null
        , value float not null default 0
        , primary key (map, tournament, player, statistic)
        , foreign key (map) references map
        , foreign key (tournament, player) references player
        );

commit;
