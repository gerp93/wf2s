# TODO

What is not built or not verified yet. See [docs/distribution-plan.md](docs/distribution-plan.md) for the plan this came from.

## Not verified (needs a real machine or real people)
- A **clean-machine test**: a fresh Windows 10/11 PC or VM following only the README, including SmartScreen and the Steam Guard prompt.
  Everything so far was run on one PC, with the game already installed (the SteamCMD download itself was not re-run).
- A **real player joining** a server created from the default instance (only bots and local-only mode were seen).
- The server's own "reachable / unreachable" lines on a real online server: the Network tab's parser is tested against the exact
  message texts from the server program, but the live case has not been seen.
- **Update server** end to end (stop, SteamCMD update window, start again).
- **Update app** against a real release (the offline tests and a live swap in a throwaway install pass; the download from GitHub and the checksum from GitHub's API have not run yet). The first real test is going from the first release that contains the updater to the next one.
- The first **release** (Auto Release runs on every push to `main`; Cut Release for a chosen number) and a download of its zip on another PC.

## Decisions still open
- Can the "Wreckfest 2 Dedicated Server" tool be installed from a Steam library (Library > Tools, or `steam://install/3519390`) on a PC
  that owns the game? If yes, setup could use that copy and skip the SteamCMD login. Needs a setting for the server folder (the scripts
  assume `.\server`) and SteamCMD kept as the fallback.
- Offer to read the admin Steam ID from the local Steam install (with consent) instead of asking for it.
- Screenshots in the README quick start.

## Later
- Remote editing from other PCs (separate project): Tailscale node sharing, a "listen on" setting, per-person keys with roles, a change log.
- Move this repo onto the KVG_Standards release pipeline if a PowerShell-zip variant is added there.
