module Main exposing (..)

import Api
import Browser
import Browser.Navigation as Nav
import Cache
import Cmd.Extra exposing (..)
import Data exposing (..)
import Dict exposing (Dict)
import Http
import Model exposing (..)
import Msg exposing (..)
import Route exposing (Route)
import Session exposing (Session(..))
import Set
import Theme exposing (Theme)
import Time
import Ui
import Url


-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- INIT


type alias Flags =
    {}


init : Flags -> Url.Url -> Nav.Key -> ModelAndCmd
init flags url key =
    Model.initial key
        |> urlUpdate url



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Time.every 1000 Tick



-- UPDATE


update : Msg -> Model -> ModelAndCmd
update msg model =
    case msg of
        ThemeToggled ->
            { model | theme = Theme.opposite model.theme }
                |> withNoCmd

        LinkClicked (Browser.Internal url) ->
            model |> withCmd (Nav.pushUrl model.key (Url.toString url))

        LinkClicked (Browser.External href) ->
            model |> withCmd (Nav.load href)

        UrlChanged url ->
            model |> urlUpdate url

        Logout ->
            -- TODO destroy localStorage.session
            { model | session = Anonymous } |> withNoCmd

        TeamNameChanged newName ->
            model
                |> withNoCmd

        PlayerToggled _ ->
            model
                |> withNoCmd

        TeamSubmitted ->
            -- TODO
            model |> withNoCmd

        Tick t ->
            { model | now = t } |> withNoCmd

        LoadedTournaments (Ok tournaments) ->
            { model
                | tournaments =
                    tournaments
                        |> List.map
                            (\t ->
                                ( tournamentPk t
                                , Cache.entry model.now t
                                )
                            )
                        |> Dict.fromList
                        |> flip Dict.union model.tournaments
            }
                |> withNoCmd

        LoadedTeams (Ok teams) ->
            { model
                | teams =
                    teams
                        |> List.map
                            (\t ->
                                ( teamPk t
                                , Cache.entry model.now t
                                )
                            )
                        |> Dict.fromList
                        |> flip Dict.union model.teams
            }
                |> withNoCmd

        LoadedPlayers (Ok players) ->
            { model
                | players =
                    players
                        |> List.map
                            (\t ->
                                ( playerPk t
                                , Cache.entry model.now t
                                )
                            )
                        |> Dict.fromList
                        |> flip Dict.union model.players
            }
                |> withNoCmd

        LoadedContracts (Ok contracts) ->
            { model
                | contracts =
                    contracts
                        |> List.map
                            (\t ->
                                ( contractPk t
                                , Cache.entry model.now t
                                )
                            )
                        |> Dict.fromList
                        |> flip Dict.union model.contracts
            }
                |> withNoCmd

        _ ->
            model |> withNoCmd



-- ROUTER


urlUpdate : Url.Url -> Model -> ModelAndCmd
urlUpdate url model =
    { model
        | route = Route.fromUrl url

        -- TODO: session
    }
        |> Api.loadCaches



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "fantasy.tf2.gg"
    , body = Ui.document model
    }



-- UTIL


flip f a b =
    f b a
