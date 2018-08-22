-- install.sql

begin;

    create extension if not exists btree_gist;

    create schema fantasy_tf2;
    set search_path to fantasy_tf2;

    \ir types.sql
    \ir tables.sql
    \ir views.sql
    \ir functions.sql
    \ir security.sql

commit;
