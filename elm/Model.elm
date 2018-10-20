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
    { key : Nav.Key
    , now : Time.Posix
    , session : Session
    , theme : Theme
    , route : Maybe Route
    , manageModel : Maybe ManageModel
    , tournaments : TournamentCache
    , players : PlayerCache
    , teams : TeamCache
    , contracts : ContractCache
    }


initial : Nav.Key -> Model
initial key =
    { key = key
    , now = Time.millisToPosix 0
    , session = Session.Anonymous
    , theme = Theme.spyTechRed
    , route = Nothing
    , manageModel = Nothing
    , tournaments = Dict.empty
    , players = Dict.empty
    , teams = Dict.empty
    , contracts = Dict.empty
    }
