module Model exposing (..)

import Browser.Navigation as Nav
import Page exposing (Page(..))
import Session exposing (Session(..))


type alias Model =
    { key : Nav.Key
    , page : Page
    , session : Session
    }
