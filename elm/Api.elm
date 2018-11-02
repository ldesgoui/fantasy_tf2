module Api exposing (loadCaches)

import Cache exposing (Cache)
import Cmd.Extra exposing (..)
import Data exposing (..)
import HttpBuilder as Http
import Json.Decode as JD
import Model exposing (..)
import Msg exposing (..)
import Route exposing (Route)
import Session exposing (Session)
import Time
import Util exposing (..)


apiBase : String
apiBase =
    "http://10.233.1.2/api/"


loadCaches : Model -> ModelAndCmd
loadCaches model =
    case model.route of
        Nothing ->
            model
                |> withNoCmd

        Just Route.Home ->
            model
                |> withCmd (loadTournaments model)

        Just (Route.Tournament pk) ->
            model
                |> withCmd (loadTournament model pk)
                |> addCmd (loadPlayersByTournament model pk)
                |> addCmd (loadTeamsByTournament model pk)

        Just (Route.Player pk) ->
            model
                |> withCmd (loadTournamentByRelation model pk)
                |> addCmd (loadPlayersByTournamentRelation model pk)

        Just (Route.Team pk) ->
            model
                |> withCmd (loadTournamentByRelation model pk)
                |> addCmd (loadPlayersByTournamentRelation model pk)
                |> addCmd (loadTeam model pk)
                |> addCmd (loadContractsByTeam model pk)

        Just (Route.Manage tPk) ->
            case model.session of
                Session.Manager { managerId } ->
                    let
                        pk =
                            ( tPk, managerId )
                    in
                    model
                        |> withCmd (loadTournament model tPk)
                        |> addCmd (loadPlayersByTournament model tPk)
                        |> addCmd (loadTeam model pk)
                        |> addCmd (loadContractsByTeam model pk)

                _ ->
                    model |> withNoCmd

        Just Route.Admin ->
            model
                |> withNoCmd


loadTournaments : Model -> Cmd Msg
loadTournaments model =
    let
        fresh =
            Cache.freshValues (model.now |> minutesAgo 5) model.tournaments
                |> List.map .slug
                |> String.join ","
    in
    get "tournament_view"
        |> Http.withExpectJson (JD.list decodeTournament)
        |> Http.withQueryParam "slug" ("not.in.(" ++ fresh ++ ")")
        |> Http.send LoadedTournaments


loadTournament : Model -> TournamentPk -> Cmd Msg
loadTournament model pk =
    if Cache.isFresh (model.now |> minutesAgo 5) pk model.tournaments then
        Cmd.none
    else
        get "tournament_view"
            |> Http.withQueryParam "slug" ("eq." ++ pk)
            |> Http.withExpectJson (JD.list decodeTournament)
            |> Http.send LoadedTournaments


loadTournamentByRelation : Model -> ( String, a ) -> Cmd Msg
loadTournamentByRelation model ( t, _ ) =
    loadTournament model t


loadTeamsByTournament : Model -> TournamentPk -> Cmd Msg
loadTeamsByTournament model pk =
    let
        fresh =
            Cache.freshValues (model.now |> minutesAgo 5) model.teams
                |> List.filter (\t -> t.tournament == pk && t.rank <= 50)
                |> List.map .manager
                |> String.join ","
    in
    get "team_view"
        |> Http.withQueryParam "tournament" ("eq." ++ pk)
        |> Http.withQueryParam "manager" ("not.in.(" ++ fresh ++ ")")
        |> Http.withQueryParam "rank" "lte.50"
        |> Http.withExpectJson (JD.list decodeTeam)
        |> Http.send LoadedTeams


loadTeam : Model -> TeamPk -> Cmd Msg
loadTeam model pk =
    if Cache.isFresh (model.now |> minutesAgo 5) pk model.teams then
        Cmd.none
    else
        get "team_view"
            |> Http.withQueryParam "tournament" ("eq." ++ Tuple.first pk)
            |> Http.withQueryParam "manager" ("eq." ++ Tuple.second pk)
            |> Http.withExpectJson (JD.list decodeTeam)
            |> Http.send LoadedTeams


loadPlayersByTournament : Model -> TournamentPk -> Cmd Msg
loadPlayersByTournament model pk =
    let
        fresh =
            Cache.freshValues (model.now |> minutesAgo 5) model.players
                |> List.filter (\t -> t.tournament == pk)
                |> List.map .playerId
                |> String.join ","
    in
    get "player_view"
        |> Http.withQueryParam "tournament" ("eq." ++ pk)
        |> Http.withQueryParam "player_id" ("not.in.(" ++ fresh ++ ")")
        |> Http.withExpectJson (JD.list decodePlayer)
        |> Http.send LoadedPlayers


loadPlayersByTournamentRelation : Model -> ( String, a ) -> Cmd Msg
loadPlayersByTournamentRelation model ( t, _ ) =
    loadPlayersByTournament model t


loadPlayer : Model -> PlayerPk -> Cmd Msg
loadPlayer model pk =
    if Cache.isFresh (model.now |> minutesAgo 5) pk model.players then
        Cmd.none
    else
        get "player_view"
            |> Http.withQueryParam "tournament" ("eq." ++ Tuple.first pk)
            |> Http.withQueryParam "player_id" ("eq." ++ Tuple.second pk)
            |> Http.withExpectJson (JD.list decodePlayer)
            |> Http.send LoadedPlayers


loadContractsByTeam : Model -> TeamPk -> Cmd Msg
loadContractsByTeam model pk =
    get "contract_view"
        |> Http.withQueryParam "tournament" ("eq." ++ Tuple.first pk)
        |> Http.withQueryParam "manager" ("eq." ++ Tuple.second pk)
        |> Http.withQueryParam "select" "*,start_time,end_time"
        |> Http.withExpectJson (JD.list decodeContract)
        |> Http.send LoadedContracts



-- UTIL


get path =
    Http.get (apiBase ++ path)
        |> Http.withTimeout (1000 * 30)
