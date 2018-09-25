module Page exposing (..)

import Cmd.Extra exposing (..)
import Data exposing (..)
import RemoteData exposing (RemoteData(..), WebData)
import Set exposing (Set)


type Page
    = Error { error : String }
    | Home
        (WebData
            { tournaments : List Tournament
            }
        )
    | Tournament
        (WebData
            { tournament : Tournament
            , players : List Player
            , teams : List Team
            }
        )
    | Player
        (WebData
            { tournament : Tournament
            , player : Player
            }
        )
    | Team
        (WebData
            { tournament : Tournament
            , team : Team
            , contracts : List Contract
            }
        )
    | Manage
        (WebData
            { tournament : Tournament
            , players : List Player
            , team : Team
            , contracts : List Contract
            , selectedRoster : Set String
            }
        )
    | Admin
