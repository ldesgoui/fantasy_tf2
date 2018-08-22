module App exposing (main)

import Html exposing (Html, text)
import Html.Attributes as Html
import Material
import Material.Button as Button
import Material.Options as Options
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
    { page = ErrorPage "Not Found"
    , errors =
        [ "The modulator wasn't ready for your intervention"
        , "You are really just matter from this sky"
        ]
    , session = Nothing
    , players = []
    , mdc = Material.defaultModel
    }


type Page
    = HomePage
        { topFantasyTeams : List FantasyTeam
        }
    | FantasyTeamPage
        { fantasyTeam : FantasyTeam
        , roster : List ActiveContract
        }
    | MyFantasyTeamPage
        { fantasyTeam : FantasyTeam
        , selectedRoster : Set String
        }
    | ErrorPage String


type alias FantasyTeam =
    { name : String
    , managerName : String
    , managerSteamId : String
    , score : Float
    , rank : Int
    }


type alias Player =
    { steamId : String
    , team : String
    , name : String
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
    , team : String
    , name : String
    , mainClass : String
    , price : Int
    , totalScore : Float
    , timeJoined : Time
    , timeLeft : Time
    }


init : ( Model, Cmd Msg )
init =
    defaultModel
        ! [ Material.init Mdc
          ]



-- UPDATE


type Msg
    = NoOp
    | CloseErrors
    | Mdc (Material.Msg Msg)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Mdc mdcMsg ->
            Material.update Mdc mdcMsg model

        CloseErrors ->
            { model
                | errors = []
            }
                ! []

        NoOp ->
            model ! []


subscriptions : Model -> Sub Msg
subscriptions model =
    Material.subscriptions Mdc model



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
        [ Options.styled Html.a
            [ oRoute HomeRoute
            , Typography.headline1
            ]
            [ text "Fantasy TF2"
            ]
        , Options.styled Html.a
            [ Html.href "https://tf2.gg" |> Options.attribute
            , Typography.headline4
            , Typography.adjustMargin
            ]
            [ text "presented by Essentials.TF"
            ]
        , Button.view Mdc
            "login-manage"
            model.mdc
            [ Button.ripple
            , Button.dense
            , Options.css "margin" "12px 0"
            , case model.session of
                Nothing ->
                    Options.attribute (Html.href "#")

                Just _ ->
                    oRoute MyFantasyTeamRoute
            ]
            [ case model.session of
                Nothing ->
                    text "Login"

                Just _ ->
                    text "Manage my team"
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
                , Options.css "background-color" "rgba(200, 100, 100, 0.6)"
                , Options.css "padding" "12px"
                ]
                (model.errors |> List.map (viewError model))


viewError : Model -> String -> Html Msg
viewError model error =
    Options.styled Html.div
        [ Options.css "max-width" "600px"
        , Options.css "width" "100%"
        , Options.css "margin" "auto"
        , Typography.body2
        ]
        [ text error ]


viewPage : Model -> Html Msg
viewPage model =
    case model.page of
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


viewHomePage model pageModel =
    text ""


viewFantasyTeamPage model pageModel =
    text ""


viewMyFantasyTeamPage model pageModel =
    text ""



-- ROUTE


type Route
    = HomeRoute
    | FantasyTeamRoute String
    | MyFantasyTeamRoute


route : Route -> Html.Attribute Msg
route r =
    Html.href "#"


oRoute : Route -> Options.Property c Msg
oRoute r =
    Options.attribute (Html.href "#")



-- UTILS


to : a -> b -> ( b, a )
to a b =
    ( b, a )
