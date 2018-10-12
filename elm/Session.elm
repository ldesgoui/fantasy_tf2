module Session exposing (..)


type Session
    = Anonymous
    | Manager
        { managerId : String
        }
