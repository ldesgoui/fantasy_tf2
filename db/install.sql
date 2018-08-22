-- install.sql

begin;

    create extension if not exists btree_gist;

    create schema fantasy_tf2;
    set search_path to fantasy_tf2;

    \i types.sql
    \i tables.sql
    \i views.sql
    \i functions.sql
    \i security.sql

commit;
