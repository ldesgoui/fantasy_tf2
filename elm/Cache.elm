module Cache exposing (..)

import Dict exposing (Dict)
import Time


type alias Entry value =
    { value : Maybe value
    , lastHit : Time.Posix
    }


type alias Cache key value =
    Dict key (Entry value)


freshValues : Time.Posix -> Cache key value -> List value
freshValues maxAge cache =
    cache
        |> Dict.values
        |> List.filterMap
            (\{ value, lastHit } ->
                if Time.posixToMillis lastHit > Time.posixToMillis maxAge then
                    value
                else
                    Nothing
            )


isFresh : Time.Posix -> comparable -> Cache comparable value -> Bool
isFresh maxAge key cache =
    cache
        |> Dict.get key
        |> Maybe.map
            (\{ value, lastHit } ->
                (value /= Nothing)
                    && (Time.posixToMillis lastHit > Time.posixToMillis maxAge)
            )
        |> Maybe.withDefault False


entry : Time.Posix -> value -> Entry value
entry now value =
    { lastHit = now
    , value = Just value
    }


miss : Time.Posix -> Entry value
miss now =
    { lastHit = now
    , value = Nothing
    }
