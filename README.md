# norte_taxi: Self-driving Taxi for WHIP

A self-driving taxi for FiveM servers running the **WHIP framework** (whip_core, with whip_phone optional). A player calls a car, it drives itself to the road next to them, opens its back doors, and takes them where they marked on a map. No driver is visible: the car looks like it drives on its own. It comes with **WHIP RIDE**, a ride hailing app for the whip_phone.

> **Made for WHIP only.** This resource uses whip_core exports (temporary vehicles, secure events and callbacks, payments and refunds, world prompts, the F1 wheel, the /whip settings page) and the whip_phone module API. It does not work on QBCore, ESX, Qbox or ox_core without a rewrite.

> **Vibecoded.** This project was built with an AI coding assistant (Claude Code), directed and tested in game by the Norte Roleplay team. Read the code before you run it on a live server, and expect rough edges.

## How a ride goes

1. **Call.** Type `/taxi` (a dialog asks for the pace) or `/taxi normal|fast|superfast`, or order one in the WHIP RIDE app.
2. **Spawn.** The car appears on a road out of sight. The spot is picked by the shortest drive to you, measured along the roads, so it does not spawn across a highway or a river.
3. **Pickup.** It drives to the road closest to you, comes in along the lane on your side, and stops when it enters a pickup area around you (20 m by default). It honks twice and opens both back doors.
4. **Get in.** Only the back seats can be used: F near the taxi always sends you to the back door on your side. Other players can ride along, but only the player who called it can start the ride.
5. **Start.** Press **E**. With a destination from the app, the ride starts. Without one, a map panel opens to pick it.
6. **Ride.** The car follows the roads to the destination and pulls over on the curb of the destination's side.
7. **Arrive.** The ride ends when the car enters an arrival area around the destination (25 m by default). It stops, everyone gets out, and the car drives away and despawns.

## Paces

Chosen when calling. They apply from the drive to you, not just the ride.

| Pace | Driving | Speed | App fare | Upgrade with E during the ride |
|---|---|---|---|---|
| Normal | Obeys every rule and each road speed limit | ×1.0 | ×1.0 | |
| Fast | Obeys the rules, ignores speed limits | ×1.45 | ×1.5 | $20 |
| Super fast | No traffic rules: red lights, wrong side, overtakes everything. Still stops for people | ×1.9 | ×2.2 | $50 |

## Driving

The car drives with GTA's own taxi logic: one long range task with GTA's "normal" driving style, a driver with maximum skill and no aggression. On top of that:

- **People.** Two shape tests every 100 ms watch the lane ahead (the length of the braking distance) and the sides (people about to cross). Close: it brakes. Further: it slows down. It honks at someone standing in front of it.
- **Curves and arrival.** It slows down for tight turns and in the last 120 m.
- **Getting unstuck.** It backs up after 8 s stuck, drives around the block on the other lane after 25 s, and jumps forward on its path after 50 s (with a fade if you are inside).
- **Curb stops.** It works out which side of the road you (or the destination) are on and stops on that curb, after coming in along that lane.

## WHIP RIDE (whip_phone app)

A mount mode whip_phone module (`html/phone/whipride.js`), registered by the client when whip_phone is running. It uses whip's own 3D map, seen from above.

- Tap the map (or a quick place) to mark a destination. A dashed line and the arrival area show on the map.
- Pick a pace in a list with the price and the estimated minutes of each, then confirm in a dialog.
- The fare is charged when you order and **refunded** if the ride never starts (no car, cancelled before you get in, the car could not reach you).
- During the ride the app shows the steps (Finding, On the way, Arrived, Riding), the car, the price and a Cancel button.

## Requirements

- FiveM server artifacts with Lua 5.4 (`lua54 'yes'`)
- `whip_core` (WHIP framework, `whip_requires '1.0'`)
- **Game build 3751 or later** (`sv_enforceGameBuild 3751`): the `vivanite2` model and its livery slot come with that build
- Optional: `whip_phone` for the WHIP RIDE app, `whip_fuel` (the taxi is filled up when it spawns)
- Optional: `norte_whip_theme` for the SF Pro fonts of the interface; without it the system font is used

## Installation

1. Copy the `norte_taxi` folder into your resources.
2. Add `ensure norte_taxi` to `server.cfg`, after whip_core (and after whip_phone if you use it).
3. In game: `/taxi`, or open WHIP RIDE on the phone.

## Commands and keys

| What | Default | Does |
|---|---|---|
| `/taxi [normal\|fast\|superfast]` | | Calls a taxi. Without a pace, a dialog asks for it |
| `/taxi cancel` | | Sends your taxi away |
| Get in the back seat | F | Near your taxi, always the back door on your side |
| Start the ride / go faster | E | In the taxi: starts the ride, then pays for the next pace |
| F1 wheel | | Taxi: destination (opens the map), Taxi: stop here |

Keys are FiveM key mappings: players change them in GTA's Settings > Key Bindings > FiveM.

## Configuration

`/whip` > Settings > Norte Taxi changes these live, and they survive updates. The defaults are in `norte_taxi/config.lua`.

- **Car:** model (`vivanite2`), driver model, invisible driver.
- **Calling:** spawn distance, cooldown, how long the taxi waits, timeouts.
- **Driving:** top, pickup and pull over speeds, pickup area and arrival area sizes.
- **WHIP RIDE fare:** base fare, price per km, minimum fare, road length factor.
- **Paces:** speed and fare multiplier of each pace, and the upgrade prices.
- **Destinations:** the quick places shown in the panel and in the app.

Also in `config.lua`: `Config.Livery` (the livery mod slot and colours) and `Config.Safety` (reaction time, braking, lane width, unstuck timers).

Code comments are in Portuguese. In game text is in English.

## The livery

`norte_taxi/stream/vivanite2_livery1.yft` is a WHIB taxi livery for the Karin Vivanite (`vivanite2`): pearl white, petrol green and a lime stripe. The taxi applies it on spawn (mod slot 48, index 0). The file **replaces the first livery of every vivanite2 on the server**, not just the taxis. Delete the `stream` folder to keep GTA's own paint.

## Security

The server decides everything. Every client message is a whip_core SecureEvent or SecureCallback with typed parameters and a rate limit. The server checks the player is seated in their own taxi before it accepts a destination, works out the fare from where the player stands, charges and refunds through whip_core receipts, validates the driver ped before it records it, and deletes the driver peds and the car when a ride ends or the player leaves.

## Known limits

- The pickup and the curb stops use GTA's road nodes. On one way roads the taxi can end on the far curb.
- Super fast drives without traffic rules. Expect crashes with other cars.
- The livery file is shared by every vivanite2 on the server.
- Tested on Legacy builds. Not checked on GTA V Enhanced.

## License

Code, interface and livery are licensed under **Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)**. You may use, share and change them with credit to Norte Roleplay. You may not sell them or use them for commercial purposes. See [LICENSE](LICENSE).
