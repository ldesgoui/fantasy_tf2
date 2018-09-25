-- Revert fantasy_tf2:btree_gist from pg

begin;

    drop extension btree_gist;

commit;
