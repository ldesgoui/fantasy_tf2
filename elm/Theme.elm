module Theme exposing (..)

import Css exposing (Color, rgb, rgba)


type alias Theme =
    { name : String
    , background : String
    , bright : Color
    }


spyTechBlu =
    { name = "Spytech BLU"
    , background = "/assets/bg_light.png"
    , bright = rgb 69 150 200
    }


spyTechRed =
    { name = "Spytech RED"
    , background = "/assets/bg_dark.png"
    , bright = rgb 200 69 69
    }


opposite t =
    if t /= spyTechBlu then
        spyTechBlu
    else
        spyTechRed
