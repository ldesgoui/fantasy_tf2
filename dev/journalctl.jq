# journalctl.jq

def leftpad(n): (" " * (n - length)) + .;
def colorize: [
    "\u001b[0;41m",
    "\u001b[1;31m",
    "\u001b[0;31m",
    "\u001b[1;33m",
    "\u001b[0;33m",
    "\u001b[1;30m"
][tonumber] ? // "\u001b[0m";

[ "\u001b[30;1m"
, (.__REALTIME_TIMESTAMP | tonumber / 1000000 | strftime("%T"))
, " \u001b[34;1m"
, (.SYSLOG_IDENTIFIER | leftpad(20))
, " "
, (.PRIORITY | colorize)
, (.MESSAGE | sub("/nix/store/[0-9a-z]+-"; "!"))
, "\u001b[0m"
] | join("")
