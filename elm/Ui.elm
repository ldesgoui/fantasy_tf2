module Ui exposing (..)

import Browser
import Cache exposing (Cache)
import Css exposing (..)
import Css.Global as Global exposing (global)
import Css.Transitions as T exposing (transition)
import Data exposing (..)
import Html
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, href, rel, src)
import Html.Styled.Events as Ev exposing (..)
import Html.Styled.Lazy exposing (..)
import Model exposing (Model)
import Msg exposing (Msg)
import Route exposing (Route)
import Session exposing (Session)
import Set exposing (Set)
import Theme exposing (Theme)
import Time


document : Model -> List (Html.Html Msg)
document model =
    [ node "link"
        [ rel "stylesheet"
        , href "https://fonts.googleapis.com/css?family=Roboto+Mono|Crimson+Text"
        ]
        []
    , global
        [ Global.body
            [ backgroundImage (url model.theme.background)
            , backgroundSize (px 512)
            , margin zero
            , padding2 (px 32) (px 16)
            ]
        ]
    , navigation model
    , div []
        [ text (model.errors |> Set.toList |> String.join " - ")
        ]
    , main_
        [ css
            [ displayFlex
            , flexDirection column
            , whiteSpace Css.pre
            , boxSizing borderBox
            ]
        ]
        (page model)
    , footer model
    ]
        |> node "if-you-can-read-this-i-will-sue-your-ass" []
        |> toUnstyled
        |> List.singleton


navigation : Model -> Html Msg
navigation model =
    nav
        [ css
            [ displayFlex
            , flexWrap wrap
            , justifyContent center
            ]
        ]
        [ case model.route of
            Just Route.Home ->
                empty

            _ ->
                a
                    [ css [ navigationItemStyle model.theme ]
                    , route Route.Home
                    ]
                    [ text "Home" ]
        , let
            f pk =
                a
                    [ css [ navigationItemStyle model.theme ]
                    , route <| Route.Tournament pk
                    ]
                    [ text "Tournament" ]
          in
          case model.route of
            Just (Route.Team ( t, _ )) ->
                f t

            Just (Route.Player ( t, _ )) ->
                f t

            Just (Route.Manage t) ->
                f t

            _ ->
                empty
        , if model.session /= Session.Anonymous then
            button
                [ css [ navigationItemStyle model.theme ]
                , onClick Msg.Logout
                ]
                [ text "Logout" ]
          else
            button
                [ css [ navigationItemStyle model.theme ]
                , onClick <| Msg.LinkClicked <| Browser.External "/auth/redirect"
                ]
                [ text "Login" ]
        , button
            [ css [ navigationItemStyle <| Theme.opposite model.theme ]
            , onClick Msg.ThemeToggled
            ]
            [ text "Theme" ]
        ]


footer : Model -> Html Msg
footer model =
    empty


page : Model -> List (Html Msg)
page model =
    case model.route of
        Just Route.Home ->
            homePage (homeData model)

        Just (Route.Tournament pk) ->
            tournamentPage (tournamentData model pk)

        Just (Route.Team pk) ->
            teamPage (teamData model pk)

        Just (Route.Player pk) ->
            playerPage (playerData model pk)

        Just (Route.Manage pk) ->
            managePage (manageData model pk)

        Just Route.Admin ->
            []

        Nothing ->
            pageNotFound model



-- HOME


homeData model =
    let
        tournaments =
            Cache.values model.tournaments
                |> List.sortBy (Time.posixToMillis << .startTime)

        get name =
            tournaments
                |> List.filter
                    (\t ->
                        String.startsWith name t.slug
                     -- && (t.endTime == Nothing)
                    )
                |> List.head
    in
    { isLoggedIn = model.session /= Session.Anonymous
    , theme = model.theme
    , tournaments = tournaments
    , points =
        [ ( 36, 48.6, get "i63" )
        ]
    , zones =
        [ ( 33, 53, get "i63" )
        , ( 40, 25, get "i63" )
        , ( 40, 80, get "i63" )
        , ( 76, 85, get "i63" )
        ]
    }


homePage data =
    [ div
        [ css
            [ marginTop (px 64)
            , marginBottom (px -35)
            , maxWidth (vw 100)
            , alignSelf center
            , display block
            , property "transform" "perspective(50vw) rotateX(-5deg)"
            , property "transform-origin" "top"
            , boxShadows [ "0 0px 30px 20px rgba(0, 0, 0, 0.5)" ]
            ]
        ]
        (img
            -- TODO svg
            [ src "/assets/map_world.png"
            , css [ width (pct 100), display block ]
            ]
            []
            :: (data.zones
                    |> List.map mapZone
               )
            ++ (data.points
                    |> List.map mapPoint
               )
        )
    , div
        [ css
            [ marginTop (px 64)
            ]
        ]
        [ h1
            [ css
                [ fontFamilies [ qt "Crimson Text", serif.value ]
                ]
            ]
            [ if data.isLoggedIn then
                text "Welcome back to the "
              else
                text "Welcome to the "
            , text "Gentlemann's Club For Statistical Evaluation Of Mercenary Performance "
            , text "(Fantasy TF2 for short)"
            ]
        , p []
            [ text "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Mauris elementum ultrices turpis ut volutpat. Quisque laoreet ullamcorper velit et aliquet. Praesent vel erat eleifend, facilisis ante eget, semper tortor. Sed non dolor scelerisque, vulputate lorem tempor, feugiat leo. Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus vel quam vulputate, feugiat ex vel, convallis mi. Nullam accumsan tristique placerat. Sed quis tempus purus, quis rhoncus sapien. Donec mattis dapibus consequat. Proin iaculis placerat finibus."
            ]
        ]
    , ul []
        (data.tournaments
            |> List.map tournamentListItem
        )
    ]


mapZone : ( Float, Float, Maybe Tournament ) -> Html Msg
mapZone ( top_, left_, mTournament ) =
    let
        size =
            mTournament
                |> Maybe.map .teamCount
                |> Maybe.withDefault 0
                |> (\n -> (toFloat n / 10000) + 0.1)
                |> clamp 0.1 0.2
    in
    a
        [ case mTournament of
            Just tournament ->
                route <| Route.Tournament <| tournamentPk tournament

            Nothing ->
                href "#"
        , css
            [ position absolute
            , top (pct top_)
            , left (pct left_)
            , transform <| translate2 (pct -50) (pct -50)
            , borderRadius (pct 50)
            , property "width" <| "calc((100vw - 32px) * " ++ String.fromFloat size ++ ")"
            , property "height" <| "calc((100vw - 32px) * " ++ String.fromFloat size ++ ")"
            , maxWidth (px <| 1056 * size)
            , maxHeight (px <| 1056 * size)
            , backgroundColor (rgba 255 0 0 0.3)
            , hover [ backgroundColor (rgba 255 25 25 0.6) ]
            , active [ backgroundColor (rgba 255 50 50 0.9) ]
            , T.transition [ T.backgroundColor 100 ]
            ]
        ]
        []


mapPoint : ( Float, Float, Maybe Tournament ) -> Html Msg
mapPoint ( top_, left_, mTournament ) =
    let
        size =
            mTournament
                |> Maybe.map .teamCount
                |> Maybe.withDefault 0
                |> (\n -> (toFloat n / 5000) + 0.1)
                |> clamp 0.02 0.03
    in
    a
        [ case mTournament of
            Just tournament ->
                route <| Route.Tournament <| tournamentPk tournament

            Nothing ->
                href "#"
        , css
            [ position absolute
            , top (pct top_)
            , left (pct left_)
            , transform <| translate2 (pct -50) (pct -50)
            , borderRadius (pct 50)
            , property "width" <| "calc((100vw - 32px) * " ++ String.fromFloat size ++ ")"
            , property "height" <| "calc((100vw - 32px) * " ++ String.fromFloat size ++ ")"
            , maxWidth (px <| 1056 * size)
            , maxHeight (px <| 1056 * size)
            , hover [ backgroundColor (rgba 255 255 25 0.6) ]
            , active [ backgroundColor (rgba 255 255 50 0.9) ]
            , T.transition [ T.backgroundColor 100 ]
            ]
        ]
        [ div
            [ css
                [ backgroundColor (rgba 255 255 0 1.0)
                , boxShadow5 (px 0) (px 0) (px 10) (px 5) (rgba 255 255 0 0.5)
                , width (px 5)
                , height (px 5)
                , borderRadius (pct 50)
                , top (pct 50)
                , left (pct 50)
                , position absolute
                , transform <| translate2 (pct -50) (pct -50)
                ]
            ]
            []
        ]


tournamentListItem tournament =
    li []
        [ a
            [ route <| Route.Tournament tournament.slug
            ]
            [ text tournament.name ]
        ]



-- TOURNAMENT


tournamentData model pk =
    { pk = pk
    , theme = model.theme
    , tournament = Cache.get pk model.tournaments
    , players =
        Cache.values model.players
            |> List.filter (\p -> p.tournament == pk)
            |> List.sortBy (\p -> p.rank)
    , teams =
        Cache.values model.teams
            |> List.filter (\t -> t.tournament == pk && t.rank < 50)
            |> List.sortBy (\t -> t.rank)
    }


tournamentPage data =
    case data.tournament of
        Nothing ->
            [ text "Loading" ]

        Just tournament ->
            [ div []
                [ text tournament.name
                , a [ route <| Route.Manage tournament.slug ]
                    [ text "manage ur team!" ]
                ]
            , ul []
                (data.players
                    |> List.map playerLeaderboardItem
                )
            , ul []
                (data.teams
                    |> List.map teamLeaderboardItem
                )
            ]


playerLeaderboardItem player =
    li []
        [ a
            [ route <| Route.Player ( player.tournament, player.playerId )
            ]
            [ text "#"
            , text (String.fromInt player.rank)
            , text " - "
            , text player.name
            , text " ("
            , text (String.fromFloat player.score)
            , text ")"
            ]
        ]


teamLeaderboardItem team =
    li []
        [ a
            [ route <| Route.Team ( team.tournament, team.manager )
            ]
            [ text "#"
            , text (String.fromInt team.rank)
            , text " - "
            , text team.name
            , text " ("
            , text (String.fromFloat team.score)
            , text ")"
            ]
        ]



-- TEAM


teamData model pk =
    let
        contractsAndPlayers =
            Cache.values model.contracts
                |> List.filterMap
                    (\c ->
                        if pk == ( c.tournament, c.manager ) then
                            Just ( c, Cache.get ( c.tournament, c.player ) model.players )
                        else
                            Nothing
                    )

        ( roster, contractHistory ) =
            contractsAndPlayers
                |> List.partition (\( c, _ ) -> c.endTime == Nothing)
    in
    { pk = pk
    , theme = model.theme
    , tournament = Cache.get (Tuple.first pk) model.tournaments
    , team = Cache.get pk model.teams
    , roster = roster
    , contractHistory = contractHistory
    }


teamPage data =
    case data.team of
        Nothing ->
            [ text "Loading" ]

        Just team ->
            [ div []
                [ text team.name
                , text " ranked "
                , text (String.fromInt team.rank)
                ]
            , ul []
                (data.roster
                    |> List.map rosterItem
                )
            , ul []
                (data.contractHistory
                    |> List.map contractHistoryItem
                )
            ]


rosterItem ( contract, mPlayer ) =
    case mPlayer of
        Just player ->
            li []
                [ a
                    [ route <| Route.Player ( contract.tournament, contract.player )
                    ]
                    [ text player.name ]
                ]

        _ ->
            li [] [ text "Loading" ]


contractHistoryItem ( contract, mPlayer ) =
    case mPlayer of
        Just player ->
            li []
                [ a
                    [ route <| Route.Player ( contract.tournament, contract.player )
                    ]
                    [ text player.name ]
                ]

        _ ->
            li [] [ text "Loading" ]



-- PLAYER


playerData model pk =
    let
        mPlayer =
            Cache.get pk model.players
    in
    { pk = pk
    , theme = model.theme
    , tournament = Cache.get (Tuple.first pk) model.tournaments
    , player = mPlayer
    , teammates =
        Cache.values model.players
            |> List.filter
                (\p ->
                    (pk /= ( p.tournament, p.playerId ))
                        && (Maybe.map .realTeam mPlayer == Just p.realTeam)
                )
    }


playerPage data =
    case data.player of
        Nothing ->
            [ text "Loading" ]

        Just player ->
            [ div []
                [ text player.name
                , text " ranked "
                , text (String.fromInt player.rank)
                ]
            , ul []
                (data.teammates
                    |> List.map teammatesItem
                )
            ]


teammatesItem player =
    li []
        [ a
            [ route <| Route.Player <| playerPk player
            ]
            [ text player.name ]
        ]



-- MANAGE


manageData model pk =
    {}


managePage data =
    []



--


pageNotFound model =
    [ text "Page not found"
    ]



-- STYLE


navigationItemStyle : Theme -> Style
navigationItemStyle theme =
    let
        textColor =
            rgb 232 199 191
    in
    batch
        [ backgroundColor theme.bright
        , borderColor (rgb 100 100 100)
        , borderRadius (px 5)
        , borderStyle solid
        , borderWidth (px 2)
        , borderBottomColor (rgb 150 150 150)
        , borderBottomStyle groove
        , boxSizing borderBox
        , boxShadows
            [ "inset 0 0px 10px 3px rgba(0, 0, 0, 0.5)"
            , "0 -1px 4px 1px rgba(0, 0, 0, 0.5)"
            ]
        , color textColor
        , fontFamilies [ qt "Roboto Mono", sansSerif.value ]
        , fontSize (Css.em 1)
        , fontWeight bold
        , letterSpacing (px 1.414)
        , margin (px 8)
        , padding3
            (px 9)
            (px 20)
            (px 8)
        , textAlign center
        , textDecoration none
        , textShadow4
            zero
            zero
            (px 8)
            textColor
        , textTransform uppercase
        , width (px 160)
        , active
            [ boxShadows
                [ "inset 0 1px 5px 3px rgba(0, 0, 0, 0.5)"
                , "0 -1px 2px 1px rgba(0, 0, 0, 0.5)"
                ]
            , property "filter" "brightness(120%)"
            , textShadow4
                zero
                zero
                (px 3)
                textColor
            ]
        , hover
            [ property "filter" "brightness(110%)"
            ]
        , focus
            [ outline zero
            ]
        , transition
            [ T.border 100
            , T.boxShadow 100
            , T.filter 100
            , T.textShadow 100
            ]
        ]



-- UTIL


route =
    href << Route.toString


empty =
    text ""


boxShadows : List String -> Style
boxShadows shadows =
    property "box-shadow"
        (shadows
            |> String.join ","
        )
