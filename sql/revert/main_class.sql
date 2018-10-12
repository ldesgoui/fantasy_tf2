-- Revert fantasy_tf2:main_class from pg

begin;

    drop type main_class;

commit;
