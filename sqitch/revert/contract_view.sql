-- Revert fantasy_tf2:contract_view from pg

begin;

    drop view contract_view;

commit;
