#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p "python3.withPackages(p:[p.flask p.requests p.pyjwt])"

import flask
import urllib.parse
import re
import requests
import jwt

app = flask.Flask(__name__)


@app.route("/redirect")
def redirect():
    params = urllib.parse.urlencode({
            "openid.ns":"http://specs.openid.net/auth/2.0",
            "openid.mode": "checkid_setup",
            "openid.return_to": "https://fantasy.tf2.gg/auth/verify",
            "openid.realm": "https://fantasy.tf2.gg/auth",
            "openid.identity": "http://specs.openid.net/auth/2.0/identifier_select",
            "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
        })
    return flask.redirect(f"https://steamcommunity.com/openid/login?{params}", code=303)

@app.route("/verify")
def verify():
    results = flask.request.args
    validation = {
            'openid.assoc_handle': results['openid.assoc_handle'],
            'openid.signed': results['openid.signed'],
            'openid.sig' : results['openid.sig'],
            'openid.ns': results ['openid.ns'],
        }

    for signed in results['openid.signed'].split(','):
        if f'openid.{signed}' not in validation:
            validation[f'openid.{signed}'] = results[f'openid.{signed}']

    validation['openid.mode'] = 'check_authentication'

    req = requests.post("https://steamcommunity.com/openid/login", validation)
    req.connection.close()

    if 'is_valid:true' not in req.text:
        params = urllib.parse.urlencode({
                "auth": "KO",
            })
        return flask.redirect(f"https://fantasy.tf2.gg?{params}", code=303)

    steam_id = re.search(
            'https://steamcommunity.com/openid/id/(\d+)',
            results['openid.claimed_id'],
        ).group(1)

    session_jwt = jwt.encode(
                { "role": "manager", "manager_id": steam_id },
                'JzLXhYmek1NG6WEtKHM8NIC32iZu44Vw',
                algorithm="HS256",
            ).decode('ascii')

    req = requests.get("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/",
            params=dict(
                key="B69239CE5EB5C102670808A7977AC20F",
                format="json",
                steamids=steam_id,
            ),
        )

    name = req.json()['response']['players'][0]['personaname']

    req = requests.patch(
            f"https://fantasy.tf2.gg/api/manager?steam_id={steam_id}",
            dict(name=name),
            headers=dict(authorization=f"Bearer {session_jwt}"),
        )

    req = requests.post(
            "https://fantasy.tf2.gg/api/manager",
            dict(
                steam_id=steam_id,
                name=name,
            ),
            headers=dict(authorization=f"Bearer {session_jwt}"),
        )

    params = urllib.parse.urlencode({
            "auth": "OK",
            "jwt": session_jwt,
        })

    return flask.redirect(f"https://fantasy.tf2.gg?{params}", code=303)


if __name__ == "__main__":
    app.run(port=4242)
