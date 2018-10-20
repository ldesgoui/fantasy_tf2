module Route exposing (..)

import Browser.Navigation as Nav
import Data exposing (..)
import Url
import Url.Builder as Builder
import Url.Parser as Parser exposing (..)


type Route
    = Home
    | Tournament TournamentPk
    | Player PlayerPk
    | Team TeamPk
    | Manage TournamentPk
    | Admin


fromUrl : Url.Url -> Maybe Route
fromUrl url =
    let
        parser =
            oneOf
                [ map Home top
                , map Admin (s "admin")
                , map Tournament string
                , map (\t -> Player << Tuple.pair t) (string </> s "player" </> string)
                , map (\t -> Team << Tuple.pair t) (string </> s "team" </> string)
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

                Tournament t ->
                    [ t ]

                Player ( t, p ) ->
                    [ t, "player", p ]

                Team ( t, m ) ->
                    [ t, "team", m ]

                Manage t ->
                    [ t, "manage" ]

                Admin ->
                    [ "admin" ]
    in
    Builder.absolute pieces []
