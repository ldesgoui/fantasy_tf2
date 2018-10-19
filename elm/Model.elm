module Model exposing (..)

import Browser.Navigation as Nav
import Page exposing (Page(..))
import Session exposing (Session(..))
import Theme exposing (Theme)


type alias Model =
    { key : Nav.Key
    , page : Page
    , session : Session
    , theme : Theme
    }
