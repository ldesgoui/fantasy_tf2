module Util exposing (..)

import Time


mapTimePosix fn time =
    Time.millisToPosix <|
        fn <|
            Time.posixToMillis time


minutesAgo minutes =
    mapTimePosix (\t -> t - (1000 * 60 * minutes))


secondsAgo seconds =
    mapTimePosix (\t -> t - (1000 * seconds))


flip f a b =
    f b a


divBy b a =
    a / b


addTo b a =
    a + b


isAfter now time =
    not <| isBefore now time


isBefore now time =
    Time.posixToMillis time
        < Time.posixToMillis now
