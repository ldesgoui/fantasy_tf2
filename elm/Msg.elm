module Msg exposing (..)

import Browser
import Data exposing (..)
import Model exposing (..)
import RemoteData exposing (RemoteData, WebData)
import Set exposing (Set)
import Url


type Msg
    = NothingHappened
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | Logout
    | TeamNameChanged String
    | PlayerToggled String
    | TeamSubmitted
    | LoadedHome
        (WebData
            { tournaments : List Tournament
            }
        )
    | LoadedTournament
        (WebData
            { tournament : Tournament
            , players : List Player
            , teams : List Team
            }
        )
    | LoadedPlayer
        (WebData
            { tournament : Tournament
            , player : Player
            }
        )
    | LoadedTeam
        (WebData
            { tournament : Tournament
            , team : Team
            , contracts : List Contract
            }
        )
    | LoadedManage
        (WebData
            { tournament : Tournament
            , players : List Player
            , team : Team
            , contracts : List Contract
            , selectedRoster : Set String
            }
        )


type alias ModelWithCmd =
    ( Model, Cmd Msg )
