-- security.sql

create role anonymous nologin;
create role manager nologin;
create role admin nologin bypassrls;

grant usage on schema fantasy_tf2 to anonymous;
grant select on all tables in schema fantasy_tf2 to anonymous;

grant usage on schema fantasy_tf2 to manager;
grant select on all tables in schema fantasy_tf2 to manager;
grant insert, update on manager, fantasy_team to manager;
grant execute on function fantasy_tf2.create_transaction(text, text[]) to manager;

grant all on schema fantasy_tf2 to admin;
grant all on all tables in schema fantasy_tf2 to admin;
grant all on all sequences in schema fantasy_tf2 to admin;
grant all on all functions in schema fantasy_tf2 to admin;

alter table manager enable row level security;
alter table fantasy_team enable row level security;

create policy manager_policy on manager
    using (true)
    with check (steam_id = current_setting('request.jwt.claim.manager_id', true));

create policy fantasy_team_policy on fantasy_team
    using (true)
    with check (manager = current_setting('request.jwt.claim.manager_id', true));

