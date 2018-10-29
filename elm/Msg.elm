module Msg exposing (..)

import Browser
import Data exposing (..)
import Http as Http
import Model exposing (..)
import Time
import Url


type Msg
    = NothingHappened
      -- THEME
    | ThemeToggled
      -- ROUTE
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
      -- SESSION
    | Logout
      -- API/CACHE
    | Tick Time.Posix
    | LoadedTournaments (Result Http.Error (List Tournament))
    | LoadedTeams (Result Http.Error (List Team))
    | LoadedPlayers (Result Http.Error (List Player))
    | LoadedContracts (Result Http.Error (List Contract))
    | CachePurged
    | CacheDropped
      -- MANAGE
    | TeamNameChanged String
    | PlayerToggled String
    | TeamSubmitted


type alias ModelAndCmd =
    ( Model, Cmd Msg )
