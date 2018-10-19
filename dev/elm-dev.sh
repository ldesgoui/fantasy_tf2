#! /usr/bin/env nix-shell
#! nix-shell -i sh -p entr caddy

cd "$(dirname "$0")/.."

trap "exit" INT TERM ERR
trap "kill 0" EXIT

caddy -conf dev/Caddyfile &

entr sed -i '5i<meta name="viewport" content="width=device-width, initial-scale=1.0">' index.html <<< "index.html" &

ls elm/* | entr elm make elm/Main.elm
