module App exposing (main)

import Html exposing (Html, text)
import Html.Attributes as Html
import Http
import Json.Decode
import Json.Decode.Pipeline
import Material
import Material.Button as Button
import Material.Elevation as Elevation
import Material.LayoutGrid as LayoutGrid
import Material.LinearProgress as LinearProgress
import Material.List as Lists
import Material.Options as Options
import Material.Theme as Theme
import Material.Typography as Typography
import Set exposing (Set)
import Time exposing (Time)


-- MAIN


main : Program Never Model Msg
main =
    Html.program
        { init = init
        , subscriptions = subscriptions
        , update = update
        , view = view
        }



-- INIT


type alias Model =
    { page : Page
    , errors : List String
    , session : Maybe String
    , players : List Player
    , mdc : Material.Model Msg
    }


defaultModel : Model
defaultModel =
    { page = LoadingPage

    --FantasyTeamPage
    --    (FantasyTeamPageModel
    --        { managerName = "twiikuu"
    --        , managerSteamId = "0"
    --        , name = "WARHURYEAH IS FOREVER"
    --        , rank = 1
    --        , totalScore = 69.9
    --        }
    --        []
    --    )
    , errors =
        [ "What's up, twiikuu here."
        , "This this an early version because I started this project like 4 days before I had to travel for LAN, some UI stuff might be janky but the backend is steady as a rock. If you run into issues, feel free to hit me up on twitter @twiikuu, on Discord twiikuu#0047 (or in the Essentials.tf server) or by email at twiikuu@gmail.com"
        ]
    , session = Nothing
    , players = []
    , mdc = Material.defaultModel
    }


type Page
    = LoadingPage
    | HomePage HomePageModel
    | FantasyTeamPage FantasyTeamPageModel
    | MyFantasyTeamPage MyFantasyTeamPageModel
    | ErrorPage String


type alias HomePageModel =
    { teams : List FantasyTeam
    }


type alias FantasyTeamPageModel =
    { team : FantasyTeam
    , roster : List ActiveContract
    }


type alias MyFantasyTeamPageModel =
    { fantasyTeam : FantasyTeam
    , selectedRoster : Set String
    }


type alias FantasyTeam =
    { name : String
    , managerName : String
    , managerSteamId : String
    , totalScore : Float
    , rank : Int
    }


type alias Player =
    { steamId : String
    , name : String
    , team : String
    , mainClass : String
    , price : Int
    , totalScore : Float
    , rank : Int
    , matchesPlayed : Int
    , efficiency : Float
    , efficiencyRank : Int
    }


type alias ActiveContract =
    { steamId : String
    , name : String
    , team : String
    , mainClass : String
    , price : Int
    , totalScore : Float
    , timeJoined : Time
    , timeLeft : Time
    }


init : ( Model, Cmd Msg )
init =
    let
        _ =
            Debug.log "hey" "If you're a bit of a tech head and feel like snooping, the API (powered by https://postgrest.com) is available at https://fantasy.tf2.gg/api, you should be able to use https://petstore.swagger.io on that URL to get the auto-generated docs. The code is available at https://github.com/ldesgoui/fantasy_tf2"
    in
    defaultModel
        ! [ Material.init Mdc
          , fetchPlayers
          , fetchHomePage
          ]



-- UPDATE


type Msg
    = NoOp
    | CloseErrors
    | RecvPlayers (Result Http.Error (List Player))
    | RecvHomePage (Result Http.Error (List FantasyTeam))
    | Mdc (Material.Msg Msg)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg |> Debug.log "update" of
        Mdc mdcMsg ->
            Material.update Mdc mdcMsg model

        CloseErrors ->
            { model
                | errors = []
            }
                ! []

        RecvPlayers (Ok players) ->
            { model
                | players = players
            }
                ! []

        RecvPlayers (Err Http.Timeout) ->
            { model
                | page = ErrorPage "Connection to server timed out"
            }
                ! []

        RecvPlayers (Err Http.NetworkError) ->
            { model
                | page = ErrorPage "Couldn't establish connection to server"
            }
                ! []

        RecvPlayers (Err _) ->
            { model
                | page = ErrorPage "Couldn't load player information, please contact developer on the Essentials.TF Discord or at twiikuu@gmail.com"
            }
                ! []

        RecvHomePage (Ok teams) ->
            { model
                | page = HomePage (HomePageModel teams)
            }
                ! []

        RecvHomePage (Err Http.Timeout) ->
            { model
                | page = ErrorPage "Connection to server timed out"
            }
                ! []

        RecvHomePage (Err Http.NetworkError) ->
            { model
                | page = ErrorPage "Couldn't establish connection to server"
            }
                ! []

        RecvHomePage (Err _) ->
            { model
                | page = ErrorPage "Couldn't load home page, please contact developer on the Essentials.TF Discord or at twiikuu@gmail.com"
            }
                ! []

        NoOp ->
            model ! []


subscriptions : Model -> Sub Msg
subscriptions model =
    Material.subscriptions Mdc model


api : String
api =
    "http://10.233.1.2/api"


fetchPlayers : Cmd Msg
fetchPlayers =
    Http.get
        (api ++ "/player_standing")
        (Json.Decode.list decodePlayer)
        |> Http.send RecvPlayers


fetchHomePage : Cmd Msg
fetchHomePage =
    Http.get
        (api ++ "/team_standing?limit=48")
        (Json.Decode.list decodeFantasyTeam)
        |> Http.send RecvHomePage



-- VIEW


view : Model -> Html Msg
view model =
    Html.div
        [ Html.style
            [ "display" |> to "flex"
            , "flex-flow" |> to "column"
            ]
        ]
        [ viewHeader model
        , viewErrors model
        , viewPage model
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    Html.div
        [ Html.style
            [ "display" |> to "flex"
            , "flex-flow" |> to "column"
            , "align-items" |> to "center"
            , "justify-content" |> to "center"
            , "height" |> to "auto"
            , "min-height" |> to "360px"
            ]
        ]
        [ Html.a
            [ route HomeRoute
            , Html.style
                [ "max-width" |> to "75%"
                ]
            ]
            [ Html.img
                [ Html.src "logo.png"
                , Html.style
                    [ "width" |> to "100%"
                    ]
                ]
                []
            ]
        , Button.view Mdc
            "login-manage"
            model.mdc
            [ Button.ripple
            , Button.dense
            , Options.attribute (Html.attribute "style" "--mdc-theme-primary: #6c9c2f")
            , case model.session of
                Nothing ->
                    Options.attribute (Html.href "#TODO")

                Just _ ->
                    oRoute MyFantasyTeamRoute
            ]
            [ case model.session of
                Nothing ->
                    text "Sign in through STEAM"

                Just _ ->
                    text "Manage my team"
            ]
        , Button.view Mdc
            "lan-tf-link"
            model.mdc
            [ Button.ripple
            , Button.dense
            , Button.link "https://lan.tf"
            , Options.attribute (Html.attribute "style" "--mdc-theme-primary: rgb(212, 99, 38)")
            , Options.attribute (Html.href "https://lan.tf")
            ]
            [ text "lan.tf"
            ]
        ]


viewErrors : Model -> Html Msg
viewErrors model =
    case model.errors of
        [] ->
            text ""

        errors ->
            Options.styled Html.div
                [ Options.onClick CloseErrors
                , Options.css "display" "flex"
                , Options.css "flex-flow" "column"
                , Options.css "align-items" "start"
                , Options.css "justify-content" "start"
                , Options.css "background-color" "hsla(0, 100%, 75%, 0.6)"
                , Options.css "padding" "12px"
                , Elevation.z10
                ]
                (List.append model.errors [ "Click to close messages" ]
                    |> List.map (viewError model)
                )


viewError : Model -> String -> Html Msg
viewError model error =
    Options.styled Html.div
        [ Options.css "max-width" "600px"
        , Options.css "width" "100%"
        , Options.css "margin" "5px auto"
        , Typography.body2
        ]
        [ text error ]


viewPage : Model -> Html Msg
viewPage model =
    case model.page of
        LoadingPage ->
            LinearProgress.view [ LinearProgress.indeterminate ] []

        HomePage pageModel ->
            viewHomePage model pageModel

        FantasyTeamPage pageModel ->
            viewFantasyTeamPage model pageModel

        MyFantasyTeamPage pageModel ->
            viewMyFantasyTeamPage model pageModel

        ErrorPage err ->
            Options.styled Html.div
                [ Typography.headline3
                , Options.css "max-width" "920px"
                , Options.css "margin" "20px auto"
                ]
                [ text "Wow. Great job. You caused an error: "
                , Html.br [] []
                , text err
                ]


viewHomePage : Model -> HomePageModel -> Html Msg
viewHomePage model pageModel =
    LayoutGrid.view
        []
        [ LayoutGrid.cell
            [ LayoutGrid.span6
            ]
            [ Options.styled Html.h3
                [ Typography.headline6
                , Typography.adjustMargin
                , Theme.textSecondaryOnBackground
                , Options.css "margin-left" "16px"
                ]
                [ text "Best Fantasy Teams" ]
            , Lists.ul
                [ Lists.twoLine
                , Options.css "min-width" "320px"
                ]
                (pageModel.teams
                    |> List.map viewHomePageTeam
                )
            ]
        , LayoutGrid.cell
            [ LayoutGrid.span6
            ]
            [ Options.styled Html.h3
                [ Typography.headline6
                , Typography.adjustMargin
                , Theme.textSecondaryOnBackground
                , Options.css "margin-left" "72px"
                ]
                [ text "Best Players" ]
            , Lists.ul
                [ Lists.twoLine
                , Lists.avatarList
                , Options.css "min-width" "320px"
                ]
                (model.players
                    |> List.map viewHomePagePlayer
                )
            ]
        ]


viewHomePagePlayer player =
    Lists.li []
        [ Lists.graphic
            [ Options.css "background-color" (teamColor player.team)
            ]
            [ Html.img
                [ Html.src
                    ("class/" ++ player.mainClass ++ ".png")
                , Html.style
                    [ "max-width" |> to "75%"
                    , "max-height" |> to "75%"
                    ]
                ]
                []
            ]
        , Lists.text []
            [ Options.styled Html.a
                [ Options.attribute
                    (Html.href
                        ("https://steamcommunity.com/profiles/"
                            ++ player.steamId
                        )
                    )
                , Options.attribute (Html.target "_blank")
                , Options.css "text-decoration" "none"
                , Theme.textPrimaryOnBackground
                ]
                [ text player.name
                ]
            , Lists.secondaryText []
                [ text player.team
                ]
            ]
        , Lists.meta
            []
            [ text (toString player.totalScore)
            , text " #"
            , text (toString player.rank)
            ]
        ]


viewHomePageTeam team =
    Lists.li []
        [ Lists.text []
            [ Options.styled Html.a
                [ oRoute (FantasyTeamRoute team.managerSteamId)
                , Options.css "text-decoration" "none"
                , Theme.textPrimaryOnBackground
                ]
                [ text team.name ]
            , Lists.secondaryText []
                [ Options.styled Html.a
                    [ Options.attribute
                        (Html.href
                            ("https://steamcommunity.com/profiles/"
                                ++ team.managerSteamId
                            )
                        )
                    , Options.attribute
                        (Html.target "_blank")
                    , Options.css "text-decoration" "none"
                    , Theme.textSecondaryOnBackground
                    ]
                    [ text "by "
                    , text team.managerName
                    ]
                ]
            ]
        , Lists.meta
            []
            [ text (toString team.totalScore)
            , text " #"
            , text (toString team.rank)
            ]
        ]


teamColor : String -> String
teamColor team =
    case team of
        "Se7en" ->
            "#4494ca"

        "froyotech" ->
            "#94ca42"

        "SVIFT" ->
            "black"

        "Ora Elektro" ->
            "hsl(0, 100%, 40%)"

        "The Bus Crew" ->
            "#e0c200"

        "Ascent.EU" ->
            "#00aef0"

        "FAINT Gaming" ->
            "#6f08a1"

        "Timed Out" ->
            "pink"

        _ ->
            "0"


viewFantasyTeamPage : Model -> FantasyTeamPageModel -> Html Msg
viewFantasyTeamPage model pageModel =
    text ""


viewMyFantasyTeamPage : Model -> MyFantasyTeamPageModel -> Html Msg
viewMyFantasyTeamPage model pageModel =
    text ""



-- ROUTE
-- TODO


type Route
    = HomeRoute
    | FantasyTeamRoute String
    | MyFantasyTeamRoute


route : Route -> Html.Attribute Msg
route r =
    Html.href "#TODO"


oRoute : Route -> Options.Property c Msg
oRoute r =
    Options.attribute (Html.href "#TODO")



-- UTILS


to : a -> b -> ( b, a )
to a b =
    ( b, a )



-- JSON


decodePlayer : Json.Decode.Decoder Player
decodePlayer =
    Json.Decode.Pipeline.decode Player
        |> Json.Decode.Pipeline.required "steam_id" Json.Decode.string
        |> Json.Decode.Pipeline.required "name" Json.Decode.string
        |> Json.Decode.Pipeline.required "team" Json.Decode.string
        |> Json.Decode.Pipeline.required "main_class" Json.Decode.string
        |> Json.Decode.Pipeline.required "price" Json.Decode.int
        |> Json.Decode.Pipeline.required "total_score" Json.Decode.float
        |> Json.Decode.Pipeline.required "rank" Json.Decode.int
        |> Json.Decode.Pipeline.required "matches_played" Json.Decode.int
        |> Json.Decode.Pipeline.required "efficiency" Json.Decode.float
        |> Json.Decode.Pipeline.required "efficiency_rank" Json.Decode.int


decodeFantasyTeam : Json.Decode.Decoder FantasyTeam
decodeFantasyTeam =
    Json.Decode.Pipeline.decode FantasyTeam
        |> Json.Decode.Pipeline.required "name" Json.Decode.string
        |> Json.Decode.Pipeline.required "manager_name" Json.Decode.string
        |> Json.Decode.Pipeline.required "manager" Json.Decode.string
        |> Json.Decode.Pipeline.required "total_score" Json.Decode.float
        |> Json.Decode.Pipeline.required "rank" Json.Decode.int
