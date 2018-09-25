-- Deploy fantasy_tf2:player to pg

begin;

    create table player
        ( tournament text not null
        , player_id text not null
        , name text not null
        , real_team text not null
        , main_class main_class not null
        , price int not null
        , primary key (tournament, player_id)
        , foreign key (tournament) references tournament
        , foreign key (tournament, real_team) references real_team
        );

commit;
