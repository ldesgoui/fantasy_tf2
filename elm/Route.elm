module Route exposing (..)

import Browser.Navigation as Nav
import Data exposing (..)
import Url
import Url.Builder as Builder
import Url.Parser as Parser exposing (..)


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
            oneOf
                [ map Home top
                , map Admin (s "admin")
                , map Tournament string
                , map Player (string </> s "player" </> string)
                , map Team (string </> s "team" </> string)
                , map Manage (string </> s "manage")
                ]
    in
    parse parser url


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
    Builder.absolute pieces []
