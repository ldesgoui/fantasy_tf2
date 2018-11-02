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
import Task
import Theme exposing (Theme)
import Time
import Ui
import Url
import Util exposing (..)


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
        |> addCmd (Task.perform Tick Time.now)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 1000 Tick
        , Time.every (10 * 60 * 1000) (always CachePurged)
        ]



-- UPDATE


update : Msg -> Model -> ModelAndCmd
update msg model =
    case msg of
        NothingHappened ->
            model
                |> withNoCmd

        -- THEME
        ThemeToggled ->
            { model
                | theme = Theme.opposite model.theme
            }
                |> withNoCmd

        -- ROUTE
        LinkClicked (Browser.Internal url) ->
            model
                |> withCmd (Nav.pushUrl model.key (Url.toString url))

        LinkClicked (Browser.External href) ->
            model
                |> withCmd (Nav.load href)

        UrlChanged url ->
            model
                |> urlUpdate url

        -- SESSION
        Logout ->
            { model
                | session = Anonymous
            }
                |> withCmd (saveSession Nothing)

        -- API/CACHE
        Tick now ->
            let
                refresh =
                    model.lastHttpFailure
                        |> Maybe.map
                            (\t ->
                                Time.posixToMillis
                                    (model.now
                                        |> secondsAgo
                                            (max 30 model.httpFailures)
                                    )
                                    > Time.posixToMillis t
                            )
                        |> Maybe.withDefault False
            in
            { model
                | now = now
                , lastHttpFailure =
                    if refresh then
                        Nothing
                    else
                        model.lastHttpFailure
            }
                |> (if refresh then
                        Api.loadCaches
                    else
                        withNoCmd
                   )

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
                , httpFailures = 0
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
                , httpFailures = 0
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
                , httpFailures = 0
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
                , httpFailures = 0
            }
                |> withNoCmd

        LoadedTournaments (Err err) ->
            model
                |> processHttpError err
                |> withNoCmd

        LoadedTeams (Err err) ->
            model
                |> processHttpError err
                |> withNoCmd

        LoadedPlayers (Err err) ->
            model
                |> processHttpError err
                |> withNoCmd

        LoadedContracts (Err err) ->
            model
                |> processHttpError err
                |> withNoCmd

        CachePurged ->
            let
                purgeOld =
                    Cache.purgeOld
                        (Time.millisToPosix <|
                            Time.posixToMillis model.now
                                - (1000 * 60 * 20)
                        )
            in
            { model
                | tournaments = purgeOld model.tournaments
                , teams = purgeOld model.teams
                , players = purgeOld model.players
                , contracts = purgeOld model.contracts
            }
                |> Api.loadCaches

        CacheDropped ->
            { model
                | tournaments = Dict.empty
                , teams = Dict.empty
                , players = Dict.empty
                , contracts = Dict.empty
            }
                |> Api.loadCaches

        -- MANAGE
        TeamNameChanged pk newName ->
            model
                |> updateManage pk
                    (\manage ->
                        { manage | name = newName }
                    )
                |> withNoCmd

        PlayerToggled pk playerId ->
            model
                |> updateManage pk
                    (\manage ->
                        { manage
                            | roster =
                                if Set.member playerId manage.roster then
                                    Set.remove playerId manage.roster
                                else
                                    Set.insert playerId manage.roster
                        }
                    )
                |> withNoCmd

        TeamSubmitted pk ->
            model
                |> withNoCmd

        ManageReset pk ->
            { model
                | manageModel =
                    model.manageModel
                        |> Dict.remove pk
            }
                |> withNoCmd


updateManage pk f model =
    { model
        | manageModel =
            model.manageModel
                |> Dict.update pk
                    (\m ->
                        (case m of
                            Nothing ->
                                Model.manage pk model

                            just ->
                                just
                        )
                            |> Maybe.map f
                    )
    }


urlUpdate : Url.Url -> Model -> ModelAndCmd
urlUpdate url model =
    { model
        | route = Route.fromUrl url

        -- TODO: session
    }
        |> Api.loadCaches


processHttpError : Http.Error -> Model -> Model
processHttpError err model =
    let
        insert e m =
            { m | errors = m.errors |> Set.insert e }

        increment m =
            { m
                | lastHttpFailure = Just model.now
                , httpFailures = m.httpFailures + 1
            }
    in
    case err of
        Http.BadUrl url ->
            model
                |> insert ("Developer error: invalid URL: " ++ url)

        Http.Timeout ->
            model
                |> insert "Http request timed out"
                |> increment

        Http.NetworkError ->
            model
                |> insert "You have lost connection to the internet"
                |> increment

        Http.BadPayload s resp ->
            model
                |> insert ("Developer error: invalid response schema: " ++ s)

        Http.BadStatus resp ->
            model
                |> insert ("Developer error: invalid status: " ++ resp.status.message)


saveSession : Maybe String -> Cmd Msg
saveSession token =
    Cmd.none



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "fantasy.tf2.gg"
    , body = Ui.document model
    }
