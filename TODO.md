# TODO

What is not built or not verified yet. See [docs/distribution-plan.md](docs/distribution-plan.md) for the plan this came from.

## Not verified (needs a real machine or real people)
- A **clean-machine test**: a fresh Windows 10/11 PC or VM following only the README, including SmartScreen and the Steam Guard prompt.
  Everything so far was run on one PC, with the game already installed (the SteamCMD download itself was not re-run).
- A **real player joining** a server created from the default instance (only bots and local-only mode were seen).
- The server's own "unreachable" line on a real online server. The "reachable" case was seen on a real server, and the parser is tested
  against the exact message texts from the server program for both.
- **Update server** end to end (stop, SteamCMD update window, start again). Not run: it needs a real new game build.
- **Update app** is verified: a v0.0.2 install found v0.0.3 on GitHub, downloaded it (with GitHub's checksum), swapped it and came back on
  the new version with the server data intact. Not verified: the same on an **installer-based** install, and the button clicked in a
  browser (the page's backend path was used directly).
- The **installer** (`wf2s-setup-<version>.exe`) is built and silently installed/uninstalled on a clean CI runner every time, but nobody has
  clicked through it by hand: the wizard pages, the "Set up my server now" start, the SmartScreen "Unknown publisher" prompt (it is not
  code-signed), and switching an existing zip install over to it.

## Decisions still open
- Can the "Wreckfest 2 Dedicated Server" tool be installed from a Steam library (Library > Tools, or `steam://install/3519390`) on a PC
  that owns the game? If yes, setup could use that copy and skip the SteamCMD login. Needs a setting for the server folder (the scripts
  assume `.\server`) and SteamCMD kept as the fallback.
- Offer to read the admin Steam ID from the local Steam install (with consent) instead of asking for it.
- Screenshots in the README quick start.

## Later
- Remote editing from other PCs (separate project): Tailscale node sharing, a "listen on" setting, per-person keys with roles, a change log.
- Move this repo onto the KVG_Standards release pipeline if a PowerShell-zip variant is added there.
