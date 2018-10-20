module Msg exposing (..)

import Browser
import Data exposing (..)
import Http as Http
import Model exposing (..)
import Set exposing (Set)
import Time
import Url


type Msg
    = NothingHappened
    | ThemeToggled
    | Tick Time.Posix
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | Logout
    | TeamNameChanged String
    | PlayerToggled String
    | TeamSubmitted
    | LoadedTournaments (Result Http.Error (List Tournament))
    | LoadedTeams (Result Http.Error (List Team))
    | LoadedPlayers (Result Http.Error (List Player))
    | LoadedContracts (Result Http.Error (List Contract))


type alias ModelAndCmd =
    ( Model, Cmd Msg )
