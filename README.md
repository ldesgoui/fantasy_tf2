# Fantasy TF2


This is currently a rush. Things will get better whenever I have the time.



## TODO:


A view that contains a player's current score and the number of games he's played, this is easy once Match is modeled.


A view of a fantasy_team's current score, this is the trickiest bit, you have to join and match contract timings (holy shit dude a join)


Some checks in create_transaction


Then some security:

- admin probably should be able to update everything? delete some stuff? Idk they're trusted
- manager can edit his own name, the name of his teams and he can call create_transaction(text, text[])
- anonymous can only read (think this is default? there's nothing to hide anyways)
- some python on the side to do OpenID Auth with steam and create a JWT that postgrest will slurp up
