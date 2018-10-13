#! /usr/bin/env nix-shell
#! nix-shell -i sh -p entr caddy

cd "$(dirname "$0")/.."

trap "exit" INT TERM ERR
trap "kill 0" EXIT

caddy -conf dev/Caddyfile &

ls elm/* | entr elm make elm/Main.elm
