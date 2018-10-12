-- Deploy fantasy_tf2:main_class to pg

begin;

    create type main_class as enum
        ( 'scout'
        , 'soldier'
        , 'pyro'
        , 'demoman'
        , 'heavy'
        , 'engineer'
        , 'medic'
        , 'sniper'
        , 'spy'
        );

commit;
