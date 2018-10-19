module Ui exposing (..)

import Browser
import Css exposing (..)
import Css.Global as Global exposing (global)
import Css.Transitions as T exposing (transition)
import Data exposing (..)
import Html
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (..)
import Html.Styled.Events as Ev exposing (..)
import Model exposing (Model)
import Msg exposing (Msg)
import Page exposing (Page)
import RemoteData
import Route exposing (Route)
import Session exposing (Session)
import Theme exposing (Theme)


document : Model -> List (Html.Html Msg)
document model =
    (case model.page of
        Page.Home (RemoteData.Success pageData) ->
            homePage model pageData

        Page.Tournament (RemoteData.Success pageData) ->
            tournamentPage model pageData

        Page.Team (RemoteData.Success pageData) ->
            teamPage model pageData

        Page.Player (RemoteData.Success pageData) ->
            playerPage model pageData

        Page.Manage (RemoteData.Success pageData) ->
            managePage model pageData

        Page.Error pageData ->
            errorPage model pageData

        _ ->
            errorPage model { error = "I don't know how to render this" }
    )
        |> List.append
            [ node "link"
                [ rel "stylesheet"
                , href "https://fonts.googleapis.com/css?family=Roboto+Mono|Crimson+Text"
                ]
                []
            , global
                [ Global.body
                    [ backgroundImage (url model.theme.background)
                    , backgroundSize (px 512)
                    ]
                ]
            ]
        |> node "if-you-can-read-this-i-will-sue-your-ass" []
        |> toUnstyled
        |> List.singleton


navigation : Model -> Html Msg
navigation model =
    nav
        [ css
            [ displayFlex
            , flexWrap Css.wrap
            , justifyContent center
            ]
        ]
        [ case model.page of
            Page.Home _ ->
                empty

            _ ->
                a
                    [ css [ navigationItemStyle model.theme ]
                    , route Route.Home
                    ]
                    [ text "Home" ]
        , let
            f tournament =
                a
                    [ css [ navigationItemStyle model.theme ]
                    , route <| Route.Tournament tournament.slug
                    ]
                    [ text tournament.name ]
          in
          case model.page of
            Page.Team (RemoteData.Success { tournament }) ->
                f tournament

            Page.Player (RemoteData.Success { tournament }) ->
                f tournament

            Page.Manage (RemoteData.Success { tournament }) ->
                f tournament

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
            , onClick Msg.ToggleTheme
            ]
            [ text "Theme" ]
        ]


footer : Model -> Html Msg
footer model =
    empty


homePage model data =
    [ navigation model
    , div
        [ css
            [ backgroundImage (url "/assets/map_world.png")
            ]
        ]
        [ img
            [ src "/assets/map_world_resolution.png"
            ]
            []
        , div [] []
        , div [] []
        , div [] []
        , div [] []
        ]
    , div []
        [ h1
            [ css
                [ fontFamilies [ qt "Crimson Text", serif.value ]
                ]
            ]
            [ if model.session /= Session.Anonymous then
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
            |> List.map (tournamentListItem model)
        )
    , footer model
    ]


tournamentListItem model tournament =
    li []
        [ a
            [ route <| Route.Tournament tournament.slug
            ]
            [ text tournament.name ]
        ]


tournamentPage model data =
    [ navigation model
    , div []
        [ text data.tournament.name
        , a [ route <| Route.Manage data.tournament.slug ]
            [ text "manage ur team!" ]
        ]
    , ul []
        (data.players
            |> List.map (playerLeaderboardItem model)
        )
    , ul []
        (data.teams
            |> List.map (teamLeaderboardItem model)
        )
    , footer model
    ]


playerLeaderboardItem model player =
    li []
        [ a
            [ route <| Route.Player player.tournament player.playerId
            ]
            [ text player.name ]
        ]


teamLeaderboardItem model team =
    li []
        [ a
            [ route <| Route.Team team.tournament team.manager
            ]
            [ text team.name ]
        ]


teamPage model data =
    [ navigation model
    , footer model
    ]


playerPage model data =
    [ navigation model
    , footer model
    ]


managePage model data =
    [ navigation model
    , footer model
    ]


errorPage model data =
    [ navigation model
    , footer model
    ]



-- STYLE


navigationItemStyle : Theme -> Style
navigationItemStyle theme =
    let
        textColor =
            rgb 232 199 191
    in
    Css.batch
        [ backgroundColor theme.bright
        , borderColor (rgb 107 106 101)
        , borderRadius (px 5)
        , borderStyle solid
        , borderWidth (px 2)
        , boxShadow5 (px 0) (px 1) (px 10) (px 3) (rgba 0 0 0 0.5)
        , boxShadow6 inset (px 0) (px 1) (px 10) (px 3) (rgba 0 0 0 0.5)
        , color textColor
        , fontFamilies [ qt "Roboto Mono", sansSerif.value ]
        , fontSize (Css.em 1)
        , fontWeight bold
        , letterSpacing (px 1.414)
        , margin (Css.em 1)
        , padding2 (px 8) (px 11.31)
        , textAlign center
        , textDecoration none
        , textShadow4 zero zero (px 8) textColor
        , textTransform uppercase
        , active
            [ Css.property "filter" "brightness(120%)"
            , textShadow4 zero zero (px 3) textColor
            , boxShadow6 inset (px 0) (px 1) (px 5) (px 3) (rgba 0 0 0 0.5)
            ]
        , hover
            [ Css.property "filter" "brightness(110%)"
            ]
        , focus
            [ outline zero
            ]
        , transition
            [ T.filter 100
            , T.textShadow 100
            , T.boxShadow 100
            ]
        ]



-- UTIL


route =
    href << Route.toString


empty =
    text ""
