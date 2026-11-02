# Cortex Drone

**[Product page](https://gsdmods.com/scripts/cortex-drone?utm_source=github&utm_medium=social&utm_campaign=cortex-drone-launch)** · [All GSD scripts](https://gsdmods.com/scripts?utm_source=github&utm_medium=social&utm_campaign=cortex-drone-launch) · [Docs](https://gsdmods.com/docs?utm_source=github&utm_medium=social&utm_campaign=cortex-drone-launch) · [Discord](https://discord.com/invite/gsdmods) · [Download](https://github.com/IEver3st/cortex-drone/releases/latest)

Free, by [GSD Modifications](https://gsdmods.com/?utm_source=github&utm_medium=social&utm_campaign=cortex-drone-launch). This repository is the public release build: the files a server runs, nothing else.

Deployable drones for FiveM, built on a folding camera quadcopter model. Toss it up from your inventory, fly it through a gimbal-stabilised camera, and keep your body standing in the world with the controller in hand.

- Three drone types out of the box: **Camera drone**, **Police drone** (night, thermal, 16x zoom, target tracking and follow, plate and ID lookup, taser) and **FPV drone** (fast, agile, no obstacle sensing, built for Acro). An explosive strike payload is available for any type in the config
- Cine, Normal and Sport flight modes, plus hold-to-boost
- Acro mode on every drone (X), two styles. Glide (the default) keeps the drone level for you and answers the keys straight away: it leans to speed up, banks into turns and stops in under a second when you let go, and flips or rolls under your control with Shift + W A S D or by looking where you want to go and holding W to dive or climb along the camera (keep pushing past straight up or down for a loop), levelling out the moment you let go (first person only; in the chase view the mouse just moves the camera). Manual turns stabilisation off completely: the camera fixed to the airframe, real thrust and gravity
- A gimbal that stays level while the airframe tilts, and a chase view
- Cinematic mode (H) for recording footage: the HUD clears, the camera and flight ease in and out, and the drone flies automatic shots around a locked subject (Track, Follow, Orbit, Dronie, Rocket, Helix). Film me hands your character back and the drone films you while you walk or drive. Optional 9:16 crop guide for TikTok and Reels, or 2.39:1 letterbox bars
- Signal that fades with distance and behind buildings, with an automatic return home when it drops out
- Return-to-Home that flies back and lands at your feet, even after you leave the controls
- Lock onto any spot on the ground and orbit it with A / D while the camera stays on it
- GEO no-fly zones that push the drone back (Fort Zancudo, Bolingbroke, LSIA and Humane Labs by default)
- Battery per drone (each drone item keeps its own charge, also when traded or seized) that drains faster in Sport and with each powered accessory (spotlight, thermal, night vision, lock, taser shots), and recharges while the drone is packed away; standard and high-capacity battery items
- Battery swaps by hand: set the drone down, check the old charge on the battery's LEDs, click the clamp on the side of the battery (a pulsing ring marks it) and drag the pack out with the mouse, set it down (you can pick it up and move it again until the new one is in), then pick up the new one, bring it over the bay until it locks and let go so it clicks in and watch the LEDs fill. The old pack goes back in your bag with its charge and recharges there; the inventory shows its charge bar and when it will be full. Nearby players see it too
- Cortex livery: CORTEX and the viewfinder mark on the nose, CORTEX and CX-1 on the arms, mint stripes and hazard bands, and a CX / B1 tag on the battery
- A spotlight that everyone nearby sees: off at launch until switched on (`Config.spotlight.onAtLaunch`), under-slung so it never points above the horizon, swinging after the camera
- Obstacle sensing that brakes before walls and ceilings, and cameras that never look through them
- A pilot HUD that tells you what you need: the street and area under the drone, how long the flight home takes (it turns sand, then red, when the battery would run short), the gap to whatever is ahead along your flight path when it gets close, the rangefinder distance, and a crosshair only while the taser is ready
- Target lock that needs line of sight and lets go when the target disappears
- The drone can be shot down or crashed, picked up when it lands, and seized by police
- Standalone or Qbox (qb-core and ox_inventory supported), English plus every locale in `locales/`

## Requirements

- OneSync
- `cortex-lib` started before this resource
- Optional: `qbx_core` or `qb-core`, `ox_inventory`, `oxmysql` (plate owner lookup on Qbox)

## Install

1. Put `cortex-drone` in your resources and add `ensure cortex-drone` after `ensure cortex-lib` (and after your framework and inventory).
2. Add the items to your inventory (below).
3. Restart the server. The drone model, handling and metadata stream from the resource.

### Items

ox_inventory (`ox_inventory/data/items.lua`):

```lua
['drone'] = { label = 'Camera drone', weight = 900, stack = false, consume = 0, server = { export = 'cortex-drone.useItem' } },
['drone_police'] = { label = 'Police drone', weight = 1100, stack = false, consume = 0, server = { export = 'cortex-drone.useItem' } },
['drone_fpv'] = { label = 'FPV drone', weight = 800, stack = false, consume = 0, server = { export = 'cortex-drone.useItem' } },
['drone_battery'] = { label = 'Drone battery', weight = 300, stack = true, consume = 0, server = { export = 'cortex-drone.useItem' } },
['drone_battery_hc'] = { label = 'High-capacity drone battery', weight = 450, stack = true, consume = 0, server = { export = 'cortex-drone.useItem' } },
```

Inventory icons for the drone and both batteries are in `images/` (`drone.png`, `drone_battery.png`, `drone_battery_hc.png`); copy them into your inventory's image folder (`ox_inventory/web/images`).

With Qbox or qb-core the items are made usable automatically; you only need them to exist in your item list. Without any inventory, `Config.requireItem = 'auto'` lets players use `/drone`, `/drone police` and `/drone fpv`.

### Convars

| Convar | Use |
| --- | --- |
| `set cortex_drone_webhook "https://discord.com/api/webhooks/..."` | Optional Discord audit log (server only, never sent to clients) |
| `setr cortex_drone_locale "de"` | Override `Config.Locale` |

## Controls

While flying (raw controls inside the pilot mode, overridable in `Config.controls`):

| Action | Keyboard / mouse | Controller |
| --- | --- | --- |
| Move | W A S D | Left stick |
| Turn / tilt camera | Mouse | Right stick |
| Climb / descend | Space / Left Ctrl | RT / LT |
| Boost (hold) | Left Shift | A |
| Flight mode C / N / S | C | R3 |
| Zoom | Wheel, Arrow up / down | D-pad up / down |
| Vision (normal, night, thermal) | Q | RB |
| Spotlight | F | D-pad right |
| Lock target, then follow, then release | Left mouse | X |
| Orbit a locked ground point (aim at open ground, then lock) | A / D | Left stick |
| Payload (taser, or hold to arm and press to detonate) | Right mouse | Y |
| Chase view | V | Back |
| Return home / cancel | Z | D-pad left |
| Leave the controls | Backspace | B |
| Acro mode on / off (types with `acro = true`) | X | LB |
| Cinematic mode on / off (types with `features.cinematic`) | H | L3 |
| In cinematic: next shot | Right mouse | Y |
| In cinematic: Film me on / off | X | LB |

Climb from the ground to start the motors; the drone lifts to a 1.2 m hover. Hold descend near the ground to land.

In Acro mode nothing holds the drone level or in place. With the Manual acro controls the mouse (right stick) pitches and yaws the airframe, W / S pitch and A / D roll it (left stick), and Space / Ctrl (RT / LT) add or cut thrust around the hover point: with no throttle input the motors push exactly one g along the drone's own up axis, so a tilted drone moves that way and a drone on its back is pushed down. Keep moving the mouse up, as if looking up, and it pitches over onto its back and loops (a backflip); hold A or D and it rolls. In the chase view (V) the mouse (right stick) only yaws; W / S pitch. Impacts below `Config.flight.crashSpeed` bounce it and kick it into a tumble. C, X, Z or a lost signal switch it back to the stabilised mode (an empty battery cuts the motors and it falls as it is), which levels it out while the view rolls out with it. Hold Ctrl on the ground to cut the motors (it sets down upright).

With the Glide acro controls (the default; each player picks in Cortex settings > Drone) the drone holds itself level and keeps its height, and answers the keys straight away. W A S D ask for a speed and direction and it gets there quickly (on the keyboard the speed builds the longer you hold: a tap creeps at walking pace for tight gaps, about two seconds of holding reaches full speed), tipping forward to speed up and flaring back to slow down; the lean is what moves it, so it cruises visibly nose-down. Turning with the mouse carries most of its speed round the turn (a hard flick slides a little wide) and banks it in as hard as you turn, levelling straight out when you stop turning; the view eases into the drone's roll and shows part of the nose-down lean. Let go and it flares and stops, from full speed in under a second. Space climbs fast (`climb`) and it coasts up a little when you let go. Tricks are first person only (the chase view ignores them: Shift does nothing and the mouse only moves the camera within its range) and yours to steer: hold Shift (A on a controller) with W / S to flip forward / back or A / D to roll, for as long as you hold them. To dive or climb, look where you want to go and hold W: the drone flies along the camera line (look straight down for a vertical dive), and looking around on its own never moves it. Within 10 degrees of level W keeps your height. A dive pulls out on its own and stops a metre above the ground. Keep pushing the mouse past straight up or down and, after a short stop, the drone carries on over into a loop; let the mouse rest and it unwinds to level. In a trick the drone flies where it points: tip it back and it brakes, tip it forward and it speeds up, roll it and it slides sideways, and a full flip carries your speed through; W A S D take over again as it levels. Let go mid-flip and it eases back to level, finishing the flip if it is past halfway. A trick needs 1 m of clearance below to start. Lock, obstacle sensing and boost are off. X, C, Z or a lost signal go back to normal flight.

### Cinematic mode

Press H (L3) to clear the screen for recording. Only a short `SHOT | ORBIT` tag after each change and critical warnings (signal lost, battery critical, returning home, landing, no-fly zone) stay on screen; the controls legend shows for 8 seconds and then hides. The flight mode switches to Cine (`Config.cinematic.speedMode`), mouse pans ease in and out, zoom glides, and stick moves start and stop softly. Press H again to get the full HUD back; the flight mode you had returns with it.

Lock a subject with left click (a person, a vehicle, or a spot on the ground) and the camera keeps it framed, leading a moving subject so it stays centred. The mouse then nudges the framing up to 15 degrees off centre for a rule-of-thirds shot. Right click (Y) steps through the shots:

| Shot | What the drone does | Keys during the shot |
| --- | --- | --- |
| Track | Holds where you fly it; the camera stays on the subject | Fly as normal |
| Follow | Keeps its place behind the subject (behind a car's nose, behind a walker's direction of travel) and swings round with it | W / S distance, A / D swing around, Space / Ctrl height |
| Orbit | Circles the subject at a steady radius, moving with it | A / D speed and direction, W / S radius, Space / Ctrl height |
| Dronie | Flies back and up away from the subject, then holds | Any move key stops it |
| Rocket | Climbs straight up with the camera tilting down onto the subject, then holds | Any move key stops it |
| Helix | Orbits while spiralling out and up, then holds | Any move key stops it |

If the subject goes out of sight during a shot the drone climbs until it sees it again, then eases back down a few seconds later; the lock drops after `Config.cinematic.hideGrace` seconds. Obstacle sensing, the altitude ceiling and no-fly zones stay on, and shots never take the drone closer than `Config.cinematic.minDistance` to the subject or lower than about a metre above the ground.

**Film me** (X / LB in cinematic mode): the drone locks onto you and runs the shot you picked (Follow if none), and your character is yours again: walk, run, get in a car and drive while the screen shows the drone camera. Press X again to stop; on foot you are back on the controller, in a vehicle the link ends and the drone holds where it is (`Config.flight.leave`). Backspace leaves as usual. A lost signal, low battery or landing also ends Film me. The drone keeps up to `Config.cinematic.maxSpeed` (30 m/s, about 108 km/h); drive faster and it falls behind and loses the signal.

Cortex settings > Drone > Cinematic frame adds a guide on top of the clean feed: Vertical 9:16 shades everything outside a centred 9:16 crop (crop your recording to the clear area), Letterbox 2.39:1 draws film bars.

Key mappings (Settings > Key Bindings > FiveM): **Drone: pick up or change battery** (E, only next to a landed drone; the mouse wheel picks between PICK UP DRONE and CHANGE BATTERY) and **Drone: connect or leave controls** (no default).

Job rules (`access`, `pickup.seize`) need Qbox or qb-core. On a standalone server there are no jobs, so whoever holds a drone item can fly that type (give `drone_police` only to the people who should have it), and nobody can seize someone else's drone.

## Player settings

Cortex settings (I) > Drone, per player:

| Section | Setting | Options |
|---|---|---|
| Flight | Starting flight mode | Normal (default), Cine, Sport, Acro, Last used. Acro arms on connect and switches on once the drone has lifted off (MODE shows ACRO on the ground; X disarms it). Last used remembers the mode you last picked with C or X. Race drones ignore it. |
| Flight | Boost | Hold (default) or Tap to toggle. The latch clears on Sport, Acro or cinematic mode. |
| Acro | Acro controls | Glide (default, `Config.acro.controls`) or Manual |
| Acro | Acro rates | 50-200 %: scales Manual `pitchRate`, `rollRate`, `yawRate` and the Glide `flipRate` |
| Acro | Stick expo | 0-80 %, Manual only, defaults to `Config.acro.expo` |
| Acro | FPV camera angle | 0-60 deg, Manual only, defaults to `Config.acro.cameraTilt` |
| Camera | Starting view, camera sensitivity, invert camera tilt | |
| Display | Units, controls legend, cinematic frame (Nothing, Vertical 9:16, Letterbox 2.39:1) | |

Pressing X on the ground (motors off or taking off) arms Acro the same way, so it engages as soon as the drone is up.

## Configuration

Everything lives in `config.lua`; a bad value prints one line naming the key and falls back to a safe default.

| Key | Meaning |
| --- | --- |
| `Config.model` | Vehicle model the drone spawns as (`rcmavic`) |
| `Config.command` | Chat command to deploy or reconnect (`/drone [type]`), or `false` |
| `Config.requireItem` | `true`, `false` or `'auto'` (required when an inventory is running) |
| `Config.units` | Default units for new players: `'metric'` or `'imperial'` |
| `Config.types.<type>` | One drone type: `label`, `item`, `colours` (primary, secondary paint), `access` (`false` or `{ jobs = { police = 0 }, duty = true }`), `range` (m), `maxAltitude` (m above ground), `batterySeconds` (flight time at normal draw), `zoomMax`, `health`, `features` (`night`, `thermal`, `spotlight`, `track`, `follow`, `lookup`, `cinematic`), `payload` (`false`, a taser `{ kind, count, cooldown, range }` or an explosive `{ kind, armSeconds, impactSpeed, explosion, scale }`), `speeds` per mode (`horizontal`, `vertical` m/s, `yaw` deg/s, `accel` m/s², `tilt` deg), `ignoreNoFly`, `sensing` (obstacle braking), `acro` (allows Acro mode; on for all three types) |
| `Config.battery` | `rechargeMinutes` (a standard battery from empty to full while packed away), `minimumToLaunch`, `returnAt` (automatic return home, %), `drain` multipliers (flight modes, plus `spotlight`, `thermal`, `night` and `track` added on top while each is in use, also on a landed drone you are piloting), `taserShot` (% per taser shot), `packs` (battery items: `{ item = { capacity = 1.0 } }`; capacity multiplies the type's `batterySeconds` and the recharge time, so the default `drone_battery_hc` at 1.75 flies 75% longer and recharges 75% slower; `{}` for none) |
| `Config.signal` | `fadeStart` (fraction of range where the link starts to fade; the sand end of the HUD's range tether), `obstructionPenalty`, `lostGraceSeconds`, `onLost` (`'return'`, `'hover'` or `'land'`) |
| `Config.flight` | `launchHeight` (m above ground the drone appears at), `takeoffHeight`, `crashSpeed` (impact m/s that downs the drone), `landingSpeed`, `returnAltitude`, `returnSpeed`, `leave` (`'hover'`, `'land'` or `'return'` when the pilot lets go mid-air without a lock, or when a lock kept after leaving ends), `pilotHitDropsLink` |
| `Config.launch` | Launch toss: `enabled` (false keeps the plain hover-ahead launch), `anim` (`{ dict, name, flag }` the pilot plays; flag 48 keeps it upper-body so the clip cannot turn the pilot), `grab` and `release` (clip phases 0-1 when the drone appears in the hand and when it is let go), `hold` (`bone`, `forward`, `up` in metres from that bone), `lift` (minimum upward m/s at release), `push` (minimum outward m/s at release), `maxSpeed` (cap on the throw speed), `clearance` (m between the blade tips and the nearest part of the pilot's arms, hands, head or chest before the rotors start; they start straight at hover speed and stop again if it comes back within reach during the throw; if it never gets clear it drops with the rotors still), `watch` (seconds the third-person view stays on the throw before the drone camera) |
| `Config.camera` | Gimbal `offset` on the model, `chase` distance and height, `fov`, `gimbalMin`, `gimbalMax` |
| `Config.spotlight` | Beam `distance`, `brightness`, `hardness`, `radius`, `falloff`, `colour`; `onAtLaunch`; `traverse` (`min`, `max` pitch in degrees the light can point); `slew` (deg/s) |
| `Config.track` | `hideGrace`: seconds a locked target may stay out of sight before the lock drops; `orbitMinRadius`: closest the drone orbits a locked ground point (m) |
| `Config.acro` | Acro mode. Manual: `thrust` (top thrust in g, hover is 1), `topSpeed` (m/s at full throttle, sets air drag), `pitchRate`, `rollRate`, `yawRate` (deg/s at full stick or a held key, before the player's Acro rates setting), `expo` (0 linear to 1 soft centre; the default for the Stick expo setting), `keyRamp` (s for W A S D to reach full rate), `mouse` (multiplier on the camera sensitivity setting), `cameraTilt` (FPV camera uptilt, deg; the default for the FPV camera angle setting), `tumble` (deg/s of spin an impact at crash speed adds). Glide: `cruise` (top speed W A S D ask for, m/s; 37.5 is 135 km/h), `creep` (m/s a keyboard press starts at), `keyEase` (s of holding a key to build from `creep` to `cruise`; 0 gives full speed at once), `climb` (top climb speed for Space or W along a raised camera, m/s), `tilt` (most lean, deg), `response` (how quickly it closes the gap to the speed W A S D ask for, per second), `authority` (how many times its real push the lean gives in level flight, so a moderate lean moves it briskly; 1 is true to physics and slow; it fades to 1 during tricks), `grip` (extra pull toward that speed beyond what the lean gives, m/s2; 0 leaves it to the lean alone, a softer stop; it fades out during tricks so the attitude drives the drone), `brake` (share of `tilt` it leans back to slow down when you let go, less as it slows), `carve` (share of a turn the momentum follows straight away, 0 to 1; the lean flies the rest, so hard turns slide a little wide), `flipRate` (deg/s of a Shift flip or roll), `lookFlip` (airframe degrees per degree of looking past the camera range), `float` (share of gravity held off while it is on its side or upside down), `viewPitch` (share of the nose lean the camera shows), `levelBand` (degrees either side of level where W keeps the height; the path matches the camera from twice this), `descent` (Ctrl descent speed, m/s), `diveAccel` (m/s2 a dive builds speed with), `pullOut` (m/s2 a dive plans to brake with near the ground, capped at 0.85 of what `thrust` can do), `floor` (m above the ground a dive stops), `nose` (share of the dive angle the airframe noses in, visual only), `loopDetent` (degrees of extra push past straight up or down before it loops), `lookRest` (s the mouse must rest before a look loop unwinds; shorter pauses, like lifting the mouse, keep the loop going); it also uses `thrust` and `keyRamp` (s for a keyboard Shift flip to reach `flipRate`). Both: `controls` (acro controls for players who have not picked: `glide` or `manual`) |
| `Config.cinematic` | Cinematic mode. `speedMode` (flight mode it switches to: `'cine'`, `'normal'`, `'sport'` or `false` to keep the current one), `look` (camera pan easing, 1/s; lower is smoother), `aim` (how fast the camera follows a subject, 1/s), `zoom` (zoom easing, 1/s), `ease` (seconds for stick moves to reach full speed), `maxSpeed` (m/s cap for automatic shots), `accel` (m/s² for automatic shots), `minDistance` (closest a shot flies to the subject, m), `hideGrace` (seconds a hidden subject keeps the lock), `regain` (m/s climb while the subject is hidden), `framing` (`yaw`, `pitch`: degrees the mouse can move the subject off centre), `follow` (`swing` deg/s, `distance` max m), `orbit` (`speed` m/s at the start, `radius` max m), `dronie` (`speed`, `climb` angle, `distance` m), `rocket` (`speed`, `height` m), `helix` (`speed`, `out` and `up` m/s, `radius` m where it ends), `filmMe` (allows Film me) |
| `Config.sensing` | Obstacle sensing: `margin` (m kept from walls), `radius` (probe radius), `lookahead` (s of travel probed) |
| `Config.lookup` | Lookup `range`, `plates`, `people`, `showStandaloneNames` |
| `Config.pickup` | `distance`, `othersCanSeize`, `seize` (who may seize), `loseItemWhenDestroyed` |
| `Config.swap` | Battery swap by hand. `enabled` (`false` swaps instantly), `camera` (close-up during the swap), `reach` (m from a landed drone to swap it in place), `kneel` (m from you to the drone), `anim` (`enter`, `base`, `exit` clips) |
| `Config.pilot` | Pilot animation (`flag` 49 plays it on the upper body so the pilot stands), tablet prop, `othersSeeTablet` |
| `Config.hideHud` | Hide cortex-hud while piloting; other HUDs can listen for the `cortex-drone:hud` client event (`visible` boolean) |
| `Config.rotors` | Rotor speed (0 to 1) at `idle` on spin-up, at `hover`, and at `full` throttle |
| `Config.noFly` | `{ name, x, y, radius }` zones |
| `Config.keys.pickup` | Default pickup key |
| `Config.controls` | Control IDs per device for every pilot action |
| `Config.audit` | Which events reach the console and the webhook |

## Staff commands

Restricted commands (`command` ACE, which Qbox grants admins):

| Command | Does |
| --- | --- |
| `drone_list` | Every drone out: pilot, type, state, battery |
| `drone_recall <id>` | Removes a player's drone (the item stays with them) |
| `drone_charge <id>` | Fills the battery of every drone a player carries |

## API

Server exports:

```lua
exports['cortex-drone']:GetDrone(source)          -- { netId, kind, battery, state } or nil
exports['cortex-drone']:RecallDrone(source, why)  -- true when a drone was removed
exports['cortex-drone']:SetRaceProfile(source, { kind, spawn = { x, y, z, w }, race } or nil)
-- cortex-droneraces: the next deploy of `kind` spawns at `spawn` with a full battery and no item, range, no-fly or payload rules;
-- a crash freezes the drone instead of ending the session. nil clears it
```

Client exports:

```lua
exports['cortex-drone']:IsPiloting()   -- true while the local player flies
exports['cortex-drone']:GetDrone()     -- { netId, entity, kind, battery, state, piloting } or nil
exports['cortex-drone']:Deploy(kind)   -- same as using the item ('drone', 'police', 'fpv')
exports['cortex-drone']:Disconnect()   -- leave the controls
exports['cortex-drone']:DeployRace(kind)        -- deploy under the race profile the server set (skips the client no-fly check, no toss)
exports['cortex-drone']:RaceHold(on)            -- hold a race drone on its pad (controls ignored) or release it
exports['cortex-drone']:RaceRespawn(x, y, z, h) -- put a crashed race drone back in the air at a pose, repaired, motors on
exports['cortex-drone']:RaceGo()                -- release a held race drone at the start: motors on, acro (manual or glide per the pilot's setting) locked for the race
```

Client event `cortex-drone:raceCrashed(reason)` fires instead of the crash ending the flight while a race profile is active. `reason` is `impact`, `water`, `destroyed` or `reset` (the pilot pressed the home control to respawn). Race drones stay in acro for the whole race: the acro and mode controls are locked and the drone never auto-lands.

State bags (read-only for other resources):

- Entity `cxDrone`: `{ owner, kind, light, tilt, state }` on every drone
- Player `cxDronePilot`: `true` while that player holds the controller
- Player `cxDroneSwap`: `{ token, kind, charge, fresh, net, stage }` while that player swaps a battery (`net` is the landed drone's network id, `false` when it was packed; `stage` moves from `start` to `out` when the old pack is out and `in` when the new one latched)

## Credits

Drone model by Grayson for GSD Mods.

## Download and support

Grab the latest zip from [Releases](https://github.com/IEver3st/cortex-drone/releases/latest) and keep the folder named `cortex-drone`. The same script is also free on the [GSD store](https://gsdmods.com/scripts/cortex-drone?utm_source=github&utm_medium=social&utm_campaign=cortex-drone-launch), delivered through your Cfx.re portal. Questions and bug reports go to the [GSD Discord](https://discord.com/invite/gsdmods).

## License

Free to use and modify on your own servers under the [Cortex Drone Free Use License](LICENSE). Readable source does not make it open source: do not redistribute or resell it; share the link instead.
