-- Deploy fantasy_tf2:contract_view to pg

begin;

    create view contract_view as
         select *
           from contract super;

commit;
