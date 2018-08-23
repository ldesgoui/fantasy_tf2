module App exposing (main)

import Html exposing (Html, text)
import Html.Attributes as Html
import Http
import Json.Decode
import Json.Decode.Pipeline
import Json.Encode
import Material
import Material.Button as Button
import Material.Elevation as Elevation
import Material.LayoutGrid as LayoutGrid
import Material.LinearProgress as LinearProgress
import Material.List as Lists
import Material.Options as Options
import Material.Textfield as Textfield
import Material.Theme as Theme
import Material.Typography as Typography
import Navigation
import Regex
import Set exposing (Set)
import String


-- MAIN


main : Program Never Model Msg
main =
    Navigation.program (.hash >> UrlChange)
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
    , errors = []
    , session = Just "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoibWFuYWdlciIsIm1hbmFnZXJfaWQiOiIwIn0.XKRhX2lRU15o0IYlJwraXK2u6dyuXJBpu44XMp4G1ZA"
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
    { team : FantasyTeam
    , roster : Set String
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
    }


init : Navigation.Location -> ( Model, Cmd Msg )
init loc =
    let
        _ =
            Debug.log "hey" "If you're a bit of a tech head and feel like snooping, the API (powered by https://postgrest.com) is available at https://fantasy.tf2.gg/api/, you should be able to use https://petstore.swagger.io on that URL to get the auto-generated docs. The code is available at https://github.com/ldesgoui/fantasy_tf2"

        ( newModel, cmds ) =
            changePage loc.hash defaultModel
    in
    newModel
        ! [ Material.init Mdc
          , fetchPlayers
          , cmds
          ]



-- UPDATE


type Msg
    = NoOp
    | UrlChange String
    | CloseErrors
    | RecvPlayers (Result Http.Error (List Player))
    | RecvHomePage (Result Http.Error (List FantasyTeam))
    | RecvRoster (Result Http.Error (List ActiveContract))
    | RecvFantasyTeamPage (Result Http.Error FantasyTeam)
    | RecvMyFantasyTeamPage (Result Http.Error FantasyTeam)
    | ToggleSelect String
    | ChangeFantasyTeamName String
    | SubmitTeam
    | UpdateErrors (Result Http.Error ())
    | Mdc (Material.Msg Msg)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg |> Debug.log "update" of
        Mdc mdcMsg ->
            Material.update Mdc mdcMsg model

        UrlChange hash ->
            changePage hash model

        UpdateErrors (Ok ()) ->
            model ! []

        UpdateErrors (Err Http.Timeout) ->
            { model
                | page = ErrorPage "Connection to server timed out"
            }
                ! []

        UpdateErrors (Err Http.NetworkError) ->
            { model
                | page = ErrorPage "Couldn't establish connection to server"
            }
                ! []

        UpdateErrors (Err _) ->
            { model
                | page = ErrorPage "Couldn't save your changes, please RELOAD or contact developer on the Essentials.TF Discord or at twiikuu@gmail.com"
            }
                ! []

        SubmitTeam ->
            model
                ! (case ( model.session, model.page ) of
                    ( Just session, MyFantasyTeamPage pageModel ) ->
                        [ updateName session pageModel.team.managerSteamId pageModel.team.name
                        , updateRoster session pageModel.roster
                        ]

                    _ ->
                        []
                  )

        ChangeFantasyTeamName newName ->
            { model
                | page =
                    case model.page of
                        MyFantasyTeamPage pageModel ->
                            let
                                oldTeam =
                                    pageModel.team
                            in
                            MyFantasyTeamPage
                                { pageModel
                                    | team =
                                        { oldTeam
                                            | name = newName
                                        }
                                }

                        _ ->
                            model.page
            }
                ! []

        ToggleSelect id ->
            { model
                | page =
                    case model.page of
                        MyFantasyTeamPage pageModel ->
                            MyFantasyTeamPage
                                { pageModel
                                    | roster =
                                        if Set.member id pageModel.roster then
                                            Set.remove id pageModel.roster
                                        else
                                            Set.insert id pageModel.roster
                                }

                        _ ->
                            model.page
            }
                ! []

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

        RecvFantasyTeamPage (Ok team) ->
            { model
                | page = FantasyTeamPage (FantasyTeamPageModel team [])
            }
                ! [ fetchRoster team.managerSteamId ]

        RecvFantasyTeamPage (Err Http.Timeout) ->
            { model
                | page = ErrorPage "Connection to server timed out"
            }
                ! []

        RecvFantasyTeamPage (Err Http.NetworkError) ->
            { model
                | page = ErrorPage "Couldn't establish connection to server"
            }
                ! []

        RecvFantasyTeamPage (Err _) ->
            { model
                | page = ErrorPage "Couldn't load fantasy team page, please contact developer on the Essentials.TF Discord or at twiikuu@gmail.com"
            }
                ! []

        RecvMyFantasyTeamPage (Ok team) ->
            { model
                | page = MyFantasyTeamPage (MyFantasyTeamPageModel team Set.empty)
            }
                ! [ fetchRoster team.managerSteamId ]

        RecvMyFantasyTeamPage (Err Http.Timeout) ->
            { model
                | page = ErrorPage "Connection to server timed out"
            }
                ! []

        RecvMyFantasyTeamPage (Err Http.NetworkError) ->
            { model
                | page = ErrorPage "Couldn't establish connection to server"
            }
                ! []

        RecvMyFantasyTeamPage (Err _) ->
            { model
                | page = ErrorPage "Couldn't load manager page, please contact developer on the Essentials.TF Discord or at twiikuu@gmail.com"
            }
                ! []

        RecvRoster (Ok roster) ->
            { model
                | page =
                    case model.page of
                        FantasyTeamPage pageModel ->
                            FantasyTeamPage { pageModel | roster = roster }

                        MyFantasyTeamPage pageModel ->
                            MyFantasyTeamPage
                                { pageModel
                                    | roster =
                                        roster |> List.map .steamId |> Set.fromList
                                }

                        _ ->
                            model.page
            }
                ! []

        RecvRoster (Err Http.Timeout) ->
            { model
                | page = ErrorPage "Connection to server timed out"
            }
                ! []

        RecvRoster (Err Http.NetworkError) ->
            { model
                | page = ErrorPage "Couldn't establish connection to server"
            }
                ! []

        RecvRoster (Err _) ->
            { model
                | page = ErrorPage "Couldn't load roster, please contact developer on the Essentials.TF Discord or at twiikuu@gmail.com"
            }
                ! []

        NoOp ->
            model ! []


changePage : String -> Model -> ( Model, Cmd Msg )
changePage hash model =
    case hashToRoute hash of
        Just HomeRoute ->
            { model
                | page = LoadingPage
            }
                ! [ fetchHomePage ]

        Just (FantasyTeamRoute id) ->
            { model
                | page = LoadingPage
            }
                ! [ fetchFantasyTeamRoute id
                  ]

        Just MyFantasyTeamRoute ->
            { model
                | page = LoadingPage
            }
                ! (case model.session of
                    Just session ->
                        [ fetchMyFantasyTeamRoute session ]

                    Nothing ->
                        []
                  )

        _ ->
            { model
                | page = ErrorPage "URL not found"
            }
                ! []


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


fetchRoster : String -> Cmd Msg
fetchRoster managerId =
    Http.get
        (api ++ "/active_contract_value?order=main_class&manager=eq." ++ managerId)
        (Json.Decode.list decodeActiveContract)
        |> Http.send RecvRoster


fetchFantasyTeamRoute : String -> Cmd Msg
fetchFantasyTeamRoute id =
    Http.request
        { method = "GET"
        , headers =
            [ Http.header "Accept" "application/vnd.pgrst.object+json"
            ]
        , url = api ++ "/team_standing?limit=1&manager=eq." ++ id
        , body = Http.emptyBody
        , expect = Http.expectJson decodeFantasyTeam
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.send RecvFantasyTeamPage


fetchMyFantasyTeamRoute : String -> Cmd Msg
fetchMyFantasyTeamRoute session =
    Http.request
        { method = "GET"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ session)
            , Http.header "Accept" "application/vnd.pgrst.object+json"
            ]
        , url = api ++ "/rpc/my_team_standing"
        , body = Http.emptyBody
        , expect = Http.expectJson decodeFantasyTeam
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.send RecvMyFantasyTeamPage


updateName : String -> String -> String -> Cmd Msg
updateName session id name =
    Http.request
        { method = "PATCH"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ session)
            ]
        , url = api ++ "/fantasy_team?manager=eq." ++ id
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ "name" |> to (Json.Encode.string name)
                    ]
                )
        , expect = Http.expectStringResponse (\_ -> Ok ())
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.send UpdateErrors


updateRoster : String -> Set String -> Cmd Msg
updateRoster session roster =
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ session)
            ]
        , url = api ++ "/rpc/create_transaction"
        , body =
            Http.jsonBody
                (Json.Encode.object
                    [ "tnm" |> to (Json.Encode.string "i63")
                    , "new_roster"
                        |> to
                            (roster
                                |> Set.toList
                                |> List.map Json.Encode.string
                                |> Json.Encode.list
                            )
                    ]
                )
        , expect = Http.expectStringResponse (\_ -> Ok ())
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.send UpdateErrors



-- VIEW


view : Model -> Html Msg
view model =
    Options.styled Html.div
        [ Options.css "display" "flex"
        , Options.css "flex-flow" "column"
        , Options.attribute (Html.attribute "style" "--mdc-theme-primary: rgb(212, 99, 38)")
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
        , Html.div
            [ Html.style
                [ "display" |> to "flex"
                , "flex-flow" |> to "row"
                , "align-items" |> to "center"
                , "justify-content" |> to "center"
                ]
            ]
            [ Button.view Mdc
                "login-manage"
                model.mdc
                [ Button.ripple
                , Button.dense
                , Options.attribute (Html.attribute "style" "--mdc-theme-primary: #6c9c2f")
                , Options.css "margin" "4px"
                , case model.session of
                    Nothing ->
                        Options.attribute (Html.href "#TODO")

                    Just _ ->
                        Button.link (routeToHash MyFantasyTeamRoute)
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
                , Options.attribute (Html.target "_blank")
                , Options.css "margin" "4px"
                ]
                [ text "lan.tf"
                ]
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
        [ Elevation.z4
        ]
        [ LayoutGrid.cell
            [ LayoutGrid.span6
            , LayoutGrid.span8Tablet
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
                , Options.css "min-width" "280px"
                ]
                (pageModel.teams
                    |> List.map viewHomePageTeam
                )
            ]
        , LayoutGrid.cell
            [ LayoutGrid.span6
            , LayoutGrid.span8Tablet
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
                , Options.css "min-width" "280px"
                ]
                (model.players
                    |> List.map viewHomePagePlayer
                )
            ]
        ]


viewHomePagePlayer : Player -> Html Msg
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


viewHomePageTeam : FantasyTeam -> Html Msg
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


viewFantasyTeamPage : Model -> FantasyTeamPageModel -> Html Msg
viewFantasyTeamPage model pageModel =
    LayoutGrid.view
        [ Elevation.z1
        ]
        [ LayoutGrid.cell
            [ LayoutGrid.span6
            , LayoutGrid.span8Tablet
            , Options.cs "fantasy-team--description"
            ]
            [ Options.styled Html.h3
                [ Typography.headline5
                , Typography.adjustMargin
                ]
                [ text pageModel.team.name ]
            , Options.styled Html.a
                [ Typography.headline6
                , Typography.adjustMargin
                , Theme.textSecondaryOnBackground
                , Options.attribute
                    (Html.href
                        ("https://steamcommunity.com/profiles/"
                            ++ pageModel.team.managerSteamId
                        )
                    )
                , Options.attribute (Html.target "_blank")
                ]
                [ text "managed by "
                , text pageModel.team.managerName
                ]
            , Options.styled Html.p
                [ Typography.body1
                ]
                [ text "total score: "
                , text (toString pageModel.team.totalScore)
                ]
            , Options.styled Html.p
                [ Typography.body1
                ]
                [ text "rank #"
                , text (toString pageModel.team.rank)
                ]
            ]
        , LayoutGrid.cell
            [ LayoutGrid.span6
            , LayoutGrid.span8Tablet
            ]
            [ Lists.ul
                [ Lists.twoLine
                , Lists.avatarList
                , Options.css "min-width" "280px"
                ]
                (pageModel.roster
                    |> List.map viewFantasyTeamPagePlayer
                )
            ]
        ]


viewFantasyTeamPagePlayer : ActiveContract -> Html Msg
viewFantasyTeamPagePlayer player =
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
            [ Lists.text []
                [ Options.styled Html.div
                    [ Options.css "text-align" "right"
                    , Theme.textPrimaryOnBackground
                    ]
                    [ text (toString player.totalScore) ]
                , Lists.secondaryText
                    [ Options.css "text-align" "right"
                    ]
                    [ text "$"
                    , text (toString player.price)
                    ]
                ]
            ]
        ]


viewMyFantasyTeamPage : Model -> MyFantasyTeamPageModel -> Html Msg
viewMyFantasyTeamPage model pageModel =
    LayoutGrid.view
        [ Elevation.z1
        ]
        [ LayoutGrid.cell
            [ LayoutGrid.span12
            , Typography.body1
            ]
            [ Html.p []
                [ text "Hello, "
                , Html.a
                    [ Html.href
                        ("https://steamcommunity.com/profiles/"
                            ++ pageModel.team.managerSteamId
                        )
                    ]
                    [ text pageModel.team.managerName ]
                ]
            , Html.p []
                [ text "Please note that transfers (selling a player) are limited 6 and more are unlocked during the tournament. I haven't had the time to show counters on this page, so... good luck."
                ]
            , Html.p []
                [ text "Apologies for the raw/unfinished UI, I'm having to rush things to make it in time. You might have to give it trial and error, not all the logic is programmed on the UI but it's definitely present in the server, so if you make mistakes, they won't be saved"
                ]
            , Html.p []
                [ text "Your total score is "
                , text (toString pageModel.team.totalScore)
                , text ", your rank is #"
                , text (toString pageModel.team.rank)
                ]
            , Html.p []
                [ text "Your budget is $130000, your selected roster is worth $"
                , text
                    (toString
                        (List.foldr
                            (\a b ->
                                if Set.member a.steamId pageModel.roster then
                                    a.price + b
                                else
                                    b
                            )
                            0
                            model.players
                        )
                    )
                ]
            , Html.p []
                [ text "Thanks for playing, I hope you enjoy yourself participating and watching i63"
                ]
            ]
        , LayoutGrid.cell
            [ LayoutGrid.span12
            , Options.css "display" "flex"
            , Options.css "flex-flow" "row"
            , Options.css "align-items" "baseline"
            , Options.css "justify-content" "center"
            ]
            [ Textfield.view Mdc
                "my-fantasy-team-name"
                model.mdc
                [ Textfield.label "My Fantasy Team Name"
                , Textfield.value pageModel.team.name
                , Options.onInput ChangeFantasyTeamName
                , Options.css "margin" "0 12px"
                ]
                []
            , Button.view Mdc
                "submit-my-fantasy-team"
                model.mdc
                [ Button.ripple
                , Options.onClick SubmitTeam
                , Options.css "margin" "0 12px"
                ]
                [ text "Submit changes"
                ]
            ]
        , LayoutGrid.cell
            [ LayoutGrid.span4
            ]
            [ Lists.ul
                [ Lists.twoLine
                , Lists.avatarList
                , Options.css "min-width" "280px"
                ]
                (model.players
                    |> List.filter (\p -> p.mainClass == "scout")
                    |> List.map (viewMyFantasyTeamPagePlayer pageModel.roster)
                )
            ]
        , LayoutGrid.cell
            [ LayoutGrid.span4
            ]
            [ Lists.ul
                [ Lists.twoLine
                , Lists.avatarList
                , Options.css "min-width" "280px"
                ]
                (model.players
                    |> List.filter (\p -> p.mainClass == "soldier")
                    |> List.map (viewMyFantasyTeamPagePlayer pageModel.roster)
                )
            ]
        , LayoutGrid.cell
            [ LayoutGrid.span4
            , LayoutGrid.span8Tablet
            ]
            [ Lists.ul
                [ Lists.twoLine
                , Lists.avatarList
                , Options.css "min-width" "280px"
                ]
                (model.players
                    |> List.filter (\p -> p.mainClass == "demoman" || p.mainClass == "medic")
                    |> List.sortBy .mainClass
                    |> List.map (viewMyFantasyTeamPagePlayer pageModel.roster)
                )
            ]
        ]


viewMyFantasyTeamPagePlayer : Set String -> Player -> Html Msg
viewMyFantasyTeamPagePlayer selectedPlayers player =
    Lists.li
        [ Lists.selected
            |> Options.when (Set.member player.steamId selectedPlayers)
        , Options.onClick (ToggleSelect player.steamId)
        ]
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
            [ text player.name
            , Lists.secondaryText []
                [ text player.team
                ]
            ]
        , Lists.meta
            []
            [ Lists.text []
                [ Options.styled Html.div
                    [ Options.css "text-align" "right"
                    , Theme.textPrimaryOnBackground
                    ]
                    [ text (toString player.totalScore) ]
                , Lists.secondaryText
                    [ Options.css "text-align" "right"
                    ]
                    [ text "$"
                    , text (toString player.price)
                    ]
                ]
            ]
        ]



-- ROUTE


type Route
    = HomeRoute
    | FantasyTeamRoute String
    | MyFantasyTeamRoute


hashToRoute : String -> Maybe Route
hashToRoute hash =
    case hash of
        "" ->
            Just HomeRoute

        "#" ->
            Just HomeRoute

        "#manage" ->
            Just MyFantasyTeamRoute

        _ ->
            if Regex.contains (Regex.regex "^#\\d*$") hash then
                Just (FantasyTeamRoute (String.dropLeft 1 hash))
            else
                Nothing


routeToHash : Route -> String
routeToHash r =
    case r of
        HomeRoute ->
            "#"

        FantasyTeamRoute id ->
            "#" ++ id

        MyFantasyTeamRoute ->
            "#manage"


route : Route -> Html.Attribute a
route r =
    Html.href (routeToHash r)


oRoute : Route -> Options.Property a b
oRoute r =
    Options.attribute (route r)



-- UTILS


to : a -> b -> ( b, a )
to a b =
    ( b, a )


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


decodeActiveContract : Json.Decode.Decoder ActiveContract
decodeActiveContract =
    Json.Decode.Pipeline.decode ActiveContract
        |> Json.Decode.Pipeline.required "steam_id" Json.Decode.string
        |> Json.Decode.Pipeline.required "name" Json.Decode.string
        |> Json.Decode.Pipeline.required "team" Json.Decode.string
        |> Json.Decode.Pipeline.required "main_class" Json.Decode.string
        |> Json.Decode.Pipeline.required "price" Json.Decode.int
        |> Json.Decode.Pipeline.required "total_score" Json.Decode.float
