-- tables.sql

create table tournament
    ( slug                  text primary key
    , name                  text not null
    , budget                int not null
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

create table match
    ( id                    int primary key
    , tournament            text not null references tournament
    , time                  timestamp not null
    , name                  text not null
    );

create table match_performance
    ( match                 int references match
    , tournament            text not null references tournament
    , player                text not null
    , game_win              bool not null
    , round_win             int not null
    , frag                  int not null
    , medic_frag            int not null
    , frag_as_medic         int not null
    , dpm                   float not null
    , ubercharge            int not null
    , ubercharge_dropped    int not null
    , team_medic_death      int not null
    , top_frag              bool not null
    , top_damage            bool not null
    , top_kdr               bool not null
    , airshot               int not null
    , capture               int not null
    , foreign key (tournament, player) references player
    );

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
