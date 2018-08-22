module App exposing (main)

import Time exposing (Time)
import Set exposing (Set)
import Html exposing (..)

type alias Model =
    { page : Page
    , errors : List String
    , session : String
    , players : List Player
    }

type Route
    = HomeRoute
    | FantasyTeamRoute String
    | MyFantasyTeamRoute

type Page
    = HomePage
        { topFantasyTeams : List FantasyTeam
        }
    | FantasyTeamPage
        { fantasyTeam : FantasyTeam
        , roster : List ActiveContract
        -- , history : List Contract
        }
    | MyFantasyTeamPage
        { fantasyTeam : FantasyTeam
        , selectedRoster : Set String
        }
    | ErrorPage String

type alias FantasyTeam =
    { name : String
    , managerName : String
    , managerSteamId : String
    , score : Float
    , rank : Int
    }

type alias Player =
    { steamId : String
    , team : String
    , name : String
    , mainClass : String
    , price : Int
    , totalScore : Float
    , rank : Int
    , matchesPlayed : Int
    , efficiency : Float
    , efficiencyRank : Int
    }

type alias ActiveContract =
    { steamId : String
    , team : String
    , name : String
    , mainClass : String
    , price : Int
    , totalScore : Float
    , timeJoined : Time
    , timeLeft : Time
    }



main = text "hey"
