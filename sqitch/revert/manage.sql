-- Revert fantasy_tf2:manage from pg

begin;

    drop function manage(text, text, text[]);

commit;
