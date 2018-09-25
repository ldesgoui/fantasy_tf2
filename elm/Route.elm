module Route exposing (..)

import Browser.Navigation as Nav
import Html
import Html.Attributes as Html
import Url
import Url.Parser as Parser exposing (..)


-- TODO: debug/prod


type Route
    = Home
    | Tournament String
    | Player String String
    | Team String String
    | Manage String
    | Admin


fromUrl : Url.Url -> Maybe Route
fromUrl url =
    let
        parser =
            s "frontend"
                </> s "Main.elm"
                </> oneOf
                        [ map Home top
                        , map Admin (s "admin")
                        , map Tournament string
                        , map Player (string </> s "player" </> string)
                        , map Team (string </> s "team" </> string)
                        , map Manage (string </> s "manage")
                        ]
    in
    parse parser url


href : Route -> Html.Attribute msg
href targetRoute =
    Html.href (toString targetRoute)


replaceUrl : Nav.Key -> Route -> Cmd msg
replaceUrl key route =
    Nav.replaceUrl key (toString route)


toString : Route -> String
toString route =
    let
        pieces =
            case route of
                Home ->
                    []

                Tournament tournamentSlug ->
                    [ tournamentSlug ]

                Player tournamentSlug playerId ->
                    [ tournamentSlug, "player", playerId ]

                Team tournamentSlug teamId ->
                    [ tournamentSlug, "team", teamId ]

                Manage tournamentSlug ->
                    [ tournamentSlug, "manage" ]

                Admin ->
                    [ "admin" ]
    in
    "/frontend/Main.elm/" ++ String.join "/" pieces
