module Theme exposing (..)

import Css exposing (..)


type alias Theme =
    { name : String
    , backgroundImage : String
    , backgroundColor : Color
    , button : Color
    , mapZone : Color
    , mapZoneHover : Color
    , mapZoneActive : Color
    }


spyTechBlu =
    { name = "Spytech BLU"
    , backgroundImage = "/assets/bg_light.png"
    , backgroundColor = rgb 0 0 0
    , button = rgb 69 150 200
    , mapZone = rgba 69 150 200 0.3
    , mapZoneHover = rgba 69 150 200 0.6
    , mapZoneActive = rgba 69 150 200 0.9
    }


spyTechRed =
    { name = "Spytech RED"
    , backgroundImage = "/assets/bg_dark.png"
    , backgroundColor = rgb 0 0 0
    , button = rgb 200 69 69
    , mapZone = rgba 230 30 30 0.3
    , mapZoneHover = rgba 230 30 30 0.6
    , mapZoneActive = rgba 230 30 30 0.9
    }


opposite t =
    if t /= spyTechBlu then
        spyTechBlu
    else
        spyTechRed
