module Model exposing (..)

import Browser.Navigation as Nav
import Cache exposing (Cache)
import Data exposing (..)
import Dict exposing (Dict)
import Route exposing (Route)
import Session exposing (Session)
import Set exposing (Set)
import Theme exposing (Theme)
import Time


type alias ManageModel =
    { tournament : TournamentPk
    , name : String
    , roster : Set String
    }


type alias Model =
    { errors : Set String

    -- THEME
    , theme : Theme

    -- ROUTE
    , key : Nav.Key
    , route : Maybe Route

    -- SESSION
    , session : Session

    -- API/CACHE
    , now : Time.Posix
    , httpFailures : Int
    , lastHttpFailure : Maybe Time.Posix
    , tournaments : TournamentCache
    , players : PlayerCache
    , teams : TeamCache
    , contracts : ContractCache

    -- MANAGE
    , manageModel : Maybe ManageModel
    }


initial : Nav.Key -> Model
initial key =
    { errors = Set.empty

    -- THEME
    , theme = Theme.spyTechRed

    -- ROUTE
    , key = key
    , route = Nothing

    -- SESSION
    , session = Session.Manager { managerId = "1" }

    -- API/CACHE
    , now = Time.millisToPosix 0
    , httpFailures = 0
    , lastHttpFailure = Nothing
    , tournaments = Dict.empty
    , players = Dict.empty
    , teams = Dict.empty
    , contracts = Dict.empty

    -- MANAGE
    , manageModel = Nothing
    }
