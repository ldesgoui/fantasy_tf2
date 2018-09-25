-- Deploy fantasy_tf2:map to pg

begin;

    create table map
        ( url text not null
        , match integer not null
        , primary key (url)
        , foreign key (match) references match
        );

commit;
