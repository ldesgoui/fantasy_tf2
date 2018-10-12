-- Revert fantasy_tf2:contract_view from pg

begin;

    drop function start_time(contract_view);
    drop function end_time(contract_view);
    drop materialized view contract_view;

commit;
