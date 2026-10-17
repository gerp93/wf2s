# Instance: main

This folder is the server's `--save-dir`. Track these config files here:

- `server_config.scnf`: name, password, port, event loop reference
- `default_loop.template.becl`: event rotation / track order. `default_loop.becl` is generated from it each start
  (gitignored), so edit the template.
- `settings.json`: global overrides (bots, damage, laps, ...) saved by `scripts\ui.ps1`, applied on top of the templates at start.
- `cups/*.becl`: custom cup rotations made on the settings page's Cups tab. `start.ps1` generates what the game reads from them
  (`cups-generated/` and `server_cup_config.ccnl`, both gitignored) inside this folder. The tracked cup list is
  `server_cup_config.template.ccnl`.
- `*.ccnl`: cup configs (optional)
- `server_privilege.template.sprv`: empty roles/bans skeleton. The real `server_privilege.sprv` is local
  and gitignored (it changes at runtime). It is created on first start from the template plus
  `admins.local` (gitignored, one admin SteamID64 per line).

Generate the defaults: start the server once, run `save_default_event` in its console,
then edit the generated files.
Give yourself admin from the server console: `role STEAMID64,admin`
