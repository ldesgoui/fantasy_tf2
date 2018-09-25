-- Deploy fantasy_tf2:multiplier to pg

begin;

    create table multiplier
        ( tournament text not null
        , statistic text not null
        , multiplier float not null
        , primary key (tournament, statistic)
        , foreign key (tournament) references tournament
        );

commit;
