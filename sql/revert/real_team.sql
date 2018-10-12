-- Revert fantasy_tf2:real_team from pg

begin;

    drop table real_team;

commit;
