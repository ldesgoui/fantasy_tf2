module Data exposing (..)

import Json.Decode exposing (..)
import Json.Decode.Pipeline exposing (..)
import Set


-- TODO


type alias Tournament =
    { slug : String
    , name : String
    , startTime : String
    , endTime : Maybe String
    , startBudget : Int
    , transactions : Int
    , realTeamCount : Int
    , playerCount : Int
    , teamCount : Int
    , contractCount : Int
    }


type alias Team =
    { tournament : String
    , manager : String
    , name : String
    , startBudget : Int
    , totalBudget : Int
    , remainingBudget : Int
    , transactions : Int
    }


type alias Player =
    {}


type alias Contract =
    {}



-- JSON
-- TODO


decodeTournament : Decoder Tournament
decodeTournament =
    succeed Tournament
        |> required "slug" string
        |> required "name" string
        |> required "start_time" string
        |> required "end_time" (maybe string)
        |> required "start_budget" int
        |> required "transactions" int
        |> required "real_team_count" int
        |> required "player_count" int
        |> required "team_count" int
        |> required "contract_count" int


decodeTeam : Decoder Team
decodeTeam =
    succeed Team
        |> required "tournament" string
        |> required "manager" string
        |> required "name" string
        |> required "start_budget" int
        |> required "total_budget" int
        |> required "remaining_budget" int
        |> required "transactions" int


decodePlayer : Decoder Player
decodePlayer =
    succeed {}


decodeContract : Decoder Contract
decodeContract =
    succeed {}



-- PAGE JSON


decodeHomeData =
    list decodeTournament
        |> map
            (\tournaments ->
                { tournaments = tournaments
                }
            )


decodeTournamentData =
    decodeTournament
        |> map
            (\tournament players teams ->
                { tournament = tournament
                , players = players
                , teams = teams
                }
            )
        |> required "player" (list decodePlayer)
        |> required "team_view" (list decodeTeam)


decodePlayerData =
    decodeTournament
        |> map
            (\tournament player ->
                { tournament = tournament
                , player = player
                }
            )
        |> required "player" (index 0 decodePlayer)


decodeTeamData =
    decodeTournament
        |> map
            (\tournament team contracts ->
                { tournament = tournament
                , team = team
                , contracts = contracts
                }
            )
        |> required "team_view" (index 0 decodeTeam)
        |> required "contract" (list decodeContract)


decodeManageData =
    decodeTournament
        |> map
            (\tournament players team contracts ->
                { tournament = tournament
                , players = players
                , team = team
                , contracts = contracts
                , selectedRoster = Set.empty
                }
            )
        |> required "player" (list decodePlayer)
        |> required "team_view" (index 0 decodeTeam)
        |> required "contract" (list decodeContract)
