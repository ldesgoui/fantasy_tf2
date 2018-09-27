-- Revert fantasy_tf2:private from pg

begin;

    drop schema private;

commit;
