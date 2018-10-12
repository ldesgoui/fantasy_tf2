module Data exposing (..)

import Iso8601
import Json.Decode exposing (..)
import Json.Decode.Pipeline exposing (..)
import Set
import Time


type alias Tournament =
    { slug : String
    , name : String
    , startTime : Time.Posix
    , endTime : Maybe Time.Posix
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
    , transactions : Int
    , rank : Int
    , score : Float
    , startBudget : Int
    , totalBudget : Int
    , remainingBudget : Int
    }


type alias Player =
    { tournament : String
    , playerId : String
    , realTeam : String
    , name : String
    , price : Int
    , classRank : Int
    , rank : Int
    , score : Float
    , scorePerMap : Float
    }


type alias Contract =
    { tournament : String
    , manager : String
    , player : String
    , purchasePrice : Int
    , salePrice : Maybe Int
    , startTime : Time.Posix
    , endTime : Maybe Time.Posix
    , score : Float
    , scorePerMap : Float
    }



-- JSON


decodeTournament : Decoder Tournament
decodeTournament =
    succeed Tournament
        |> required "slug" string
        |> required "name" string
        |> required "start_time" iso8601
        |> required "end_time" (maybe iso8601)
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
        |> required "transactions" int
        |> required "rank" int
        |> required "score" float
        |> required "start_budget" int
        |> required "total_budget" int
        |> required "remaining_budget" int


decodePlayer : Decoder Player
decodePlayer =
    succeed Player
        |> required "tournament" string
        |> required "player_id" string
        |> required "real_team" string
        |> required "name" string
        |> required "price" int
        |> required "rank" int
        |> required "class_rank" int
        |> required "score" float
        |> required "score_per_map" float


decodeContract : Decoder Contract
decodeContract =
    succeed Contract
        |> required "tournament" string
        |> required "manager" string
        |> required "player" string
        |> required "purchase_price" int
        |> required "sale_price" (maybe int)
        |> required "start_time" iso8601
        |> required "end_time" (maybe iso8601)
        |> required "score" float
        |> required "score_per_map" float


iso8601 : Decoder Time.Posix
iso8601 =
    andThen
        (\str ->
            case Iso8601.toTime (str ++ "Z") of
                Ok v ->
                    succeed v

                Err _ ->
                    fail "Expected ISO-8601 datetime string"
        )
        string



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
        |> required "player_view" (list decodePlayer)
        |> required "team_view" (list decodeTeam)


decodePlayerData =
    decodeTournament
        |> map
            (\tournament player ->
                { tournament = tournament
                , player = player
                }
            )
        |> required "player_view" (index 0 decodePlayer)


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
        |> required "contract_view" (list decodeContract)


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
        |> required "player_view" (list decodePlayer)
        |> required "team_view" (index 0 decodeTeam)
        |> required "contract_view" (list decodeContract)
