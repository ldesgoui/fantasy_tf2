-- Revert fantasy_tf2:contract_view from pg

begin;

    drop materialized view contract_view;

commit;
