# Instance: main

This folder is the server's `--save-dir`. Track these config files here:

- `server_config.scnf`: name, password, port, event loop reference
- `*.becl`: event rotation / track order
- `*.ccnl`: cup configs (optional)
- `server_privilege.template.sprv`: empty roles/bans skeleton. The real `server_privilege.sprv` is local
  and gitignored (it changes at runtime). It is created on first start from the template plus
  `admins.local` (gitignored, one admin SteamID64 per line).

Generate the defaults: start the server once, run `save_default_event` in its console,
then edit the generated files.
Give yourself admin from the server console: `role STEAMID64,admin`
