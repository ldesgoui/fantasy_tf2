-- Deploy fantasy_tf2:tournament_view to pg

begin;

    create view tournament_view as
         select *
           from tournament super
              , lateral (
                 select count(1) as real_team_count
                   from real_team
                  where tournament = super.slug
                      ) rt
              , lateral (
                 select count(1) as player_count
                   from player
                  where tournament = super.slug
                      ) p
              , lateral (
                 select count(1) as team_count
                   from team
                  where tournament = super.slug
                      ) t
              , lateral (
                 select count(1) as contract_count
                   from contract
                  where tournament = super.slug
                      ) c;

commit;
