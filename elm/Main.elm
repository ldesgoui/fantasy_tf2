module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Cmd.Extra exposing (..)
import Data exposing (..)
import Html
import Html.Attributes as Html
import HttpBuilder as Http
import Model exposing (..)
import Msg exposing (..)
import Page exposing (Page)
import RemoteData exposing (RemoteData(..), WebData)
import Route exposing (Route)
import Session exposing (Session(..))
import Set
import Url


-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update =
            \msg model ->
                Debug.log "post-update" (update (Debug.log "msg" msg) model)
        , subscriptions = \_ -> Sub.none
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- INIT


type alias Flags =
    {}


init : Flags -> Url.Url -> Nav.Key -> ModelWithCmd
init flags url key =
    { key = key
    , page = Page.Home NotAsked
    , session = Anonymous
    }
        |> urlUpdate url



-- UPDATE


update : Msg -> Model -> ModelWithCmd
update msg model =
    case ( msg, model.page ) of
        ( LinkClicked (Browser.Internal url), _ ) ->
            model |> withCmd (Nav.pushUrl model.key (Url.toString url))

        ( LinkClicked (Browser.External href), _ ) ->
            model |> withCmd (Nav.load href)

        ( UrlChanged url, _ ) ->
            model |> urlUpdate url

        ( Logout, _ ) ->
            -- TODO destroy localStorage.session
            { model | session = Anonymous } |> withNoCmd

        ( LoadedHome data, Page.Home _ ) ->
            { model | page = Page.Home data } |> withNoCmd

        ( LoadedTournament data, Page.Tournament _ ) ->
            { model | page = Page.Tournament data } |> withNoCmd

        ( LoadedPlayer data, Page.Player _ ) ->
            { model | page = Page.Player data } |> withNoCmd

        ( LoadedTeam data, Page.Team _ ) ->
            { model | page = Page.Team data } |> withNoCmd

        ( LoadedManage data, Page.Manage _ ) ->
            { model | page = Page.Manage data } |> withNoCmd

        ( _, _ ) ->
            model |> withNoCmd



-- ROUTER


urlUpdate : Url.Url -> Model -> ModelWithCmd
urlUpdate url model =
    case Route.fromUrl url of
        Nothing ->
            { model | page = Page.Error { error = "Page not found" } }
                |> withNoCmd

        Just Route.Home ->
            { model | page = Page.Home Loading }
                |> withCmd loadHome

        Just (Route.Tournament tournamentSlug) ->
            { model | page = Page.Tournament Loading }
                |> withCmd (loadTournament tournamentSlug)

        Just (Route.Player tournamentSlug playerId) ->
            { model | page = Page.Player Loading }
                |> withCmd (loadPlayer tournamentSlug playerId)

        Just (Route.Team tournamentSlug teamId) ->
            { model | page = Page.Team Loading }
                |> withCmd (loadTeam tournamentSlug teamId)

        Just (Route.Manage tournamentSlug) ->
            case model.session of
                Anonymous ->
                    { model | page = Page.Error { error = "You must login to manage a team" } }
                        |> withNoCmd

                Manager { managerId } ->
                    { model | page = Page.Manage Loading }
                        |> withCmd (loadManage tournamentSlug managerId)

        Just Route.Admin ->
            -- TODO
            model
                |> withNoCmd



-- HTTP


loadHome : Cmd Msg
loadHome =
    Http.get "http://10.233.1.2/api/tournament_view"
        |> Http.withExpectJson Data.decodeHomeData
        |> Http.toRequest
        |> RemoteData.sendRequest
        |> Cmd.map LoadedHome


loadTournament : String -> Cmd Msg
loadTournament slug =
    Http.get "http://10.233.1.2/api/tournament_view"
        |> Http.withQueryParam "select" "*,player(*),team_view(*)"
        |> Http.withQueryParam "slug" ("eq." ++ slug)
        |> Http.withHeader "Accept" "application/vnd.pgrst.object+json"
        |> Http.withExpectJson Data.decodeTournamentData
        |> Http.toRequest
        |> RemoteData.sendRequest
        |> Cmd.map LoadedTournament


loadPlayer : String -> String -> Cmd Msg
loadPlayer slug id =
    Http.get "http://10.233.1.2/api/tournament_view"
        |> Http.withQueryParam "select" "*,player(*)"
        |> Http.withQueryParam "slug" ("eq." ++ slug)
        |> Http.withQueryParam "player.player_id" ("eq." ++ id)
        |> Http.withHeader "Accept" "application/vnd.pgrst.object+json"
        |> Http.withExpectJson Data.decodePlayerData
        |> Http.toRequest
        |> RemoteData.sendRequest
        |> Cmd.map LoadedPlayer


loadTeam : String -> String -> Cmd Msg
loadTeam slug id =
    Http.get "http://10.233.1.2/api/tournament_view"
        |> Http.withQueryParam "select" "*,team_view(*),contract(*)"
        |> Http.withQueryParam "slug" ("eq." ++ slug)
        |> Http.withQueryParam "team.manager" ("eq." ++ id)
        |> Http.withQueryParam "contract.manager" ("eq." ++ id)
        |> Http.withHeader "Accept" "application/vnd.pgrst.object+json"
        |> Http.withExpectJson Data.decodeTeamData
        |> Http.toRequest
        |> RemoteData.sendRequest
        |> Cmd.map LoadedTeam


loadManage : String -> String -> Cmd Msg
loadManage slug id =
    Http.get "http://10.233.1.2/api/tournament_view"
        |> Http.withQueryParam "select" "*,player(*),team_view(*),contract(*)"
        |> Http.withQueryParam "slug" ("eq." ++ slug)
        |> Http.withQueryParam "team.manager" ("eq." ++ id)
        |> Http.withQueryParam "contract.manager" ("eq." ++ id)
        |> Http.withHeader "Accept" "application/vnd.pgrst.object+json"
        |> Http.withExpectJson Data.decodeManageData
        |> Http.toRequest
        |> RemoteData.sendRequest
        |> Cmd.map LoadedManage



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "fantasy.tf2.gg" -- TODO
    , body =
        -- TODO
        [ Html.node "style" [] [ Html.text "a{display:block}" ]
        , Html.a [ Route.href Route.Home ] [ Html.text "homepage" ]
        , Html.a [ Route.href (Route.Tournament "i63") ] [ Html.text "tournament" ]
        , Html.a [ Route.href (Route.Player "i63" "1") ] [ Html.text "player" ]
        , Html.a [ Route.href (Route.Team "i63" "A") ] [ Html.text "team" ]
        , Html.a [ Route.href (Route.Manage "i63") ] [ Html.text "manage" ]
        , Html.a [ Route.href Route.Admin ] [ Html.text "admin" ]
        , Html.text (Debug.toString model.session)
        , Html.br [] []
        , Html.text (Debug.toString model.page)
        ]
    }