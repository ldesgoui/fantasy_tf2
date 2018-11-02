module Ui exposing (..)

import Browser
import Cache exposing (Cache)
import Css exposing (..)
import Css.Global as Global exposing (global)
import Css.Transitions as T exposing (transition)
import Data exposing (..)
import Dict exposing (Dict)
import Html
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (..)
import Html.Styled.Events as Ev exposing (..)
import Html.Styled.Lazy exposing (..)
import Model exposing (Model)
import Msg exposing (Msg)
import Route exposing (Route)
import Session exposing (Session)
import Set exposing (Set)
import Svg.Styled as S exposing (Svg)
import Svg.Styled.Attributes as SA
import Theme exposing (Theme)
import Time
import Util exposing (..)


document : Model -> List (Html.Html Msg)
document model =
    [ node "link"
        [ rel "stylesheet"
        , href "https://fonts.googleapis.com/css?family=Roboto+Mono|Crimson+Text"
        ]
        []
    , global
        [ Global.body
            [ backgroundImage (url model.theme.backgroundImage)
            , backgroundColor model.theme.backgroundColor
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
            , flexWrap Css.wrap
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
            case model.session of
                Session.Anonymous ->
                    [ text "Please log in" ]

                Session.Manager m ->
                    managePage (manageData model pk m)

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
        -- pointData()
        [ ( 36, 48.6, get "insomnia-" )
        ]
    , zones =
        -- zoneData()
        [ ( 33, 53, get "etf2l-" )
        , ( 40, 25, get "esea-" )
        , ( 40, 80, get "asiafortress-" )
        , ( 76, 85, get "ozfortress-" )
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
            , Css.property "transform" "perspective(50vw) rotateX(-5deg)"
            , Css.property "transform-origin" "top"
            , boxShadows [ "0 0px 30px 20px rgba(0, 0, 0, 0.5)" ]
            ]
        ]
        (worldMap data)
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


worldMap data =
    [ img
        [ src "/assets/map_world.png"
        , css [ Css.width (pct 100), display block ]
        ]
        []
    , S.svg
        [ SA.css
            [ position absolute
            , top zero
            ]
        , SA.width "100%"
        , SA.height "100%"
        ]
        (S.defs
            []
            [ S.filter
                [ SA.id "point"
                , SA.width "500%"
                , SA.height "500%"
                , SA.x "-200%"
                , SA.y "-200%"
                ]
                [ S.node "feDropShadow"
                    [ SA.result "wide"
                    , SA.in_ "SourceGraphic"
                    , SA.floodColor "#ff0"
                    , SA.stdDeviation "10 10"
                    , SA.dx "0"
                    , SA.dy "0"
                    ]
                    []
                , S.node "feDropShadow"
                    [ SA.result "narrow"
                    , SA.in_ "SourceGraphic"
                    , SA.floodColor "#ff0"
                    , SA.stdDeviation "4 4"
                    , SA.dx "0"
                    , SA.dy "0"
                    ]
                    []
                , S.feMerge
                    []
                    [ S.feMergeNode [ SA.in_ "wide" ] []
                    , S.feMergeNode [ SA.in_ "wide" ] []
                    , S.feMergeNode [ SA.in_ "narrow" ] []
                    ]
                ]
            ]
            :: List.map (mapZone data.theme) data.zones
            ++ List.map mapPoint data.points
        )
    ]


mapZone : Theme -> ( Float, Float, Maybe Tournament ) -> Svg Msg
mapZone theme ( top_, left_, mTournament ) =
    let
        size =
            mTournament
                |> Maybe.map .teamCount
                |> Maybe.withDefault 0
                |> toFloat
                |> clamp 0 1000
                |> divBy 40
                |> sqrt
                |> addTo 5

        pct n =
            String.fromFloat n ++ "%"
    in
    S.a
        (case mTournament of
            Just tournament ->
                [ SA.xlinkHref <|
                    Route.toString <|
                        Route.Tournament <|
                            tournamentPk tournament
                ]

            Nothing ->
                []
        )
        [ S.circle
            [ SA.cx <| pct left_
            , SA.cy <| pct top_
            , SA.r <| pct size
            , SA.css
                [ fill theme.mapZone
                , hover [ fill theme.mapZoneHover ]
                , active [ fill theme.mapZoneActive ]
                , Css.property "transition" "fill 100ms"
                ]
            ]
            []
        ]


mapPoint : ( Float, Float, Maybe Tournament ) -> Svg Msg
mapPoint ( top_, left_, mTournament ) =
    let
        size =
            mTournament
                |> Maybe.map .teamCount
                |> Maybe.withDefault 0
                |> toFloat
                |> clamp 0 500
                |> divBy 100
                |> sqrt
                |> addTo 2

        pct n =
            String.fromFloat n ++ "%"
    in
    S.a
        (case mTournament of
            Just tournament ->
                [ SA.xlinkHref <|
                    Route.toString <|
                        Route.Tournament <|
                            tournamentPk tournament
                ]

            Nothing ->
                []
        )
        [ S.circle
            [ SA.cx <| pct left_
            , SA.cy <| pct top_
            , SA.r <| pct (size / 5)
            , SA.filter "url(#point)"
            , SA.css
                [ fill (rgba 255 255 0 1)
                ]
            ]
            []
        , S.circle
            [ SA.cx <| pct left_
            , SA.cy <| pct top_
            , SA.r <| pct size
            , SA.css
                [ fill transparent
                , hover [ fill (rgba 255 255 25 0.3) ]
                , active [ fill (rgba 255 255 50 0.6) ]
                , Css.property "transition" "fill 100ms"
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


manageData model pk manager =
    let
        team =
            Cache.get ( pk, manager.managerId ) model.teams

        contracts =
            Cache.values model.contracts
                |> List.filter
                    (\c -> c.tournament == pk && c.manager == manager.managerId)

        defaultManage =
            { tournament = pk
            , name =
                team
                    |> Maybe.map .name
                    |> Maybe.withDefault ""
            , roster =
                contracts
                    |> List.filter (\c -> c.endTime == Nothing)
                    |> List.map .player
                    |> Set.fromList
            }

        manage =
            model.manageModel
                |> Dict.get pk
                |> Maybe.withDefault defaultManage

        { scouts, soldiers, demomen, medics } =
            Cache.values model.players
                |> List.filter (\p -> p.tournament == pk)
                |> List.foldl
                    (\p a ->
                        case p.mainClass of
                            "scout" ->
                                { a | scouts = p :: a.scouts }

                            "soldier" ->
                                { a | soldiers = p :: a.soldiers }

                            "demoman" ->
                                { a | demomen = p :: a.demomen }

                            "medic" ->
                                { a | medics = p :: a.medics }

                            _ ->
                                a
                    )
                    { scouts = [], soldiers = [], demomen = [], medics = [] }
    in
    { theme = model.theme
    , pk = pk
    , tournament = Cache.get pk model.tournaments
    , scouts = scouts
    , soldiers = soldiers
    , demomen = demomen
    , medics = medics
    , team = team
    , contracts = contracts
    , manage = manage
    }


managePage data =
    let
        selectablePlayer player =
            li
                [ css [ cursor pointer ]
                , onClick (Msg.PlayerToggled data.pk player.playerId)
                ]
                [ text player.name
                , if Set.member player.playerId data.manage.roster then
                    text " (selected)"
                  else
                    text ""
                ]
    in
    [ input [ onInput (Msg.TeamNameChanged data.pk), value data.manage.name ] []
    , ul [] (List.map selectablePlayer data.scouts)
    , ul [] (List.map selectablePlayer data.soldiers)
    , ul [] (List.map selectablePlayer data.demomen)
    , ul [] (List.map selectablePlayer data.medics)
    ]



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
        [ backgroundColor theme.button
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
        , Css.width (px 160)
        , active
            [ boxShadows
                [ "inset 0 1px 5px 3px rgba(0, 0, 0, 0.5)"
                , "0 -1px 2px 1px rgba(0, 0, 0, 0.5)"
                ]
            , Css.property "filter" "brightness(120%)"
            , textShadow4
                zero
                zero
                (px 3)
                textColor
            ]
        , hover
            [ Css.property "filter" "brightness(110%)"
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
    Css.property "box-shadow"
        (shadows
            |> String.join ","
        )
