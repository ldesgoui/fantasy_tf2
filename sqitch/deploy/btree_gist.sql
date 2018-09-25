-- Deploy fantasy_tf2:btree_gist to pg

begin;

    create extension btree_gist with schema pg_catalog;

commit;
