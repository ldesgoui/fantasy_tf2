module Data exposing (..)

import Cache exposing (Cache)
import Iso8601
import Json.Decode exposing (..)
import Json.Decode.Pipeline exposing (..)
import Set
import Time


-- TOURNAMENT


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


type alias TournamentPk =
    String


tournamentPk : Tournament -> TournamentPk
tournamentPk { slug } =
    slug


type alias TournamentCache =
    Cache TournamentPk Tournament



-- TEAM


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


type alias TeamPk =
    ( String, String )


teamPk : Team -> TeamPk
teamPk { tournament, manager } =
    ( tournament, manager )


type alias TeamCache =
    Cache TeamPk Team



-- PLAYER


type alias Player =
    { tournament : String
    , playerId : String
    , realTeam : String
    , name : String
    , price : Int
    , rank : Int
    , classRank : Int
    , score : Float
    , scorePerMap : Float
    }


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


type alias PlayerPk =
    ( String, String )


playerPk : Player -> PlayerPk
playerPk { tournament, playerId } =
    ( tournament, playerId )


type alias PlayerCache =
    Cache PlayerPk Player



-- CONTRACT


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


type alias ContractPk =
    ( String, String, ( String, Int ) )


contractPk : Contract -> ContractPk
contractPk c =
    ( c.tournament, c.manager, ( c.player, Time.posixToMillis c.startTime ) )


type alias ContractCache =
    Cache ContractPk Contract



-- JSON


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
