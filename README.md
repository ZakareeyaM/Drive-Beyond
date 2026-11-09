# DRIVE BEYOND — Explore. Drive. Survive.

A 3D open-world driving game for **Android** (and desktop), built in **Godot 4.7** with **GDScript**.
Every model, texture, shader, sound effect and music track is generated in code — there are no third-party assets.

## Get the APK (GitHub Actions)
1. Create a new GitHub repository and push this folder to the `main` branch (the folder with `project.godot` must be the repo root).
2. Open the **Actions** tab → **Build Android APK**. It runs automatically on every push (or press *Run workflow*).
3. When it finishes (about 10–20 min the first time), open the run → **Artifacts → DriveBeyond-apk** → download, unzip, install `DriveBeyond.apk` on your phone (allow "install unknown apps").

If a build fails, open the failed step's log. The most common cause is the Android SDK / build-tools version that Godot expects; the workflow installs several versions, and the log tells you which one is missing — add it to the `sdkmanager` line in `.github/workflows/build-apk.yml`.

## Run on desktop
Open the folder in Godot 4.7 and press F5, or run `run_game.bat` (Windows, needs `godot` on PATH).

## Controls
| Action | Keyboard | Touch |
|---|---|---|
| Accelerate / brake-reverse | W / S | GAS / BRAKE |
| Steer | A / D | ◀ ▶ (or tilt steering in Settings) |
| Handbrake / nitro | Space / Shift | HB / N2O |
| Enter / exit vehicle, interact | E (exit also F) | USE / EXIT |
| Camera (chase, close, cockpit, hood, cinematic) | C | CAM |
| Headlights / horn / reset car | L / H / R | LGT / HORN / RST |
| Map / pause | M / Esc | MAP / II |
| On foot | WASD, Shift run, Space jump, mouse look | left stick area, right-side drag look |

All keys can be remapped in Settings → Controls.

## What is in the game
* **World**: 3.2 × 3.2 km procedurally generated map streamed in chunks — downtown grid with skyscrapers, suburbs, industrial port, highways, bridge and coast road, lighthouse, mountain pass to a summit, desert with dirt tracks and ghost town, pine forest, farmland, Apex Speedway and a drag strip. ~35 km of roads with a routing graph.
* **Vehicles (10 + police)**: hatchback, sedan, GT, rotary AWD, V8 muscle, SUV, off-roader, pickup, supercar, electric hypercar. Arcade or simulation handling, gearbox/RPM, fuel, nitro, tyre/surface grip, visible damage (dents, cracked glass, broken lights, smoke).
* **Garage & dealership**: 3D showroom, 8 performance upgrades (change real stats), paint, two-tone, wheels, rims, spoilers, bumpers, body kits, tint, headlights, underglow, plates, repair, sell, garage expansion. Cars are gated by reputation and money.
* **On-foot play**: leave the car (`[E] Enter Vehicle` prompt when near it), walk, run, jump.
* **Traffic & pedestrians**: AI cars on the road graph with traffic lights, lane changes and reactions; sidewalk pedestrians.
* **Police**: 5 wanted levels (more units, faster/skilled drivers), roadblocks from level 4, helicopter with spotlight at level 5, busted fine and escape logic. Crimes: hit-and-run, speeding cameras, red lights, hitting pedestrians/police.
* **Day / night & weather**: full cycle with sunset sky and lit windows; clear, cloudy, light rain, heavy rain, fog, thunderstorm — rain wets roads and reduces grip.
* **Missions (18)**: story chain with Rico, Vera, Marcus, Kane and Ghost; street races, time trials, drag, drift, deliveries (damage limits), driving challenges (top speed, near misses, air time), police escapes, off-road runs, plus random rival sprints. Rewards, reputation, replays.
* **Systems**: money/fuel/repair economy, hidden packages, location discovery, GPS route on minimap and map, manual + auto save with corruption protection (checksum + backup), settings with Low/Medium/High/Ultra presets, procedural audio on four buses (Music, Engine, Environment, Effects).

## Honest limitations
* **No underground parking.** The terrain is a heightfield, so true underground spaces can't be built; the rooftop parking structure is provided instead.
* Building interiors are not enterable; the garage, dealership and gas stations are drive-up locations with their own menus.
* The world is procedural and stylised (low-poly look), not photoreal. Vehicles are original designs, not licensed cars.
* Tilt steering depends on your phone's sensor orientation; use "Invert tilt" in Settings if it feels reversed. Touch layout and performance were not tested on real hardware — on weaker phones keep the **Low** preset (default on mobile) and lower *View distance*.
* The APK is a **debug-signed** build for sideloading, not a Play Store release.
* Pedestrians and police are simplified (no full ragdolls or on-foot arrests).

## Project layout
`scripts/autoload` (Game, Data) · `scripts/world` (generation, streaming, weather, world orchestrator) · `scripts/vehicles` · `scripts/traffic` · `scripts/police` · `scripts/missions` + `data/missions/missions.json` · `scripts/audio` · `scripts/ui` · `shaders` · `tests` (dev-only checks).
Missions are plain JSON — add your own entries to `data/missions/missions.json`.

## Update notes (landscape / tilt / day-night / vehicles)
- **Landscape**: `display/window/handheld/orientation=4` (sensor landscape, both landscape directions, never portrait). Previously `6` (full sensor) let Android rotate to portrait. UI uses a 1280x720 base with `canvas_items` + `expand`, so 16:9 and 20:9 phones get extra width.
- **Tilt steering** (`scripts/player/tilt_steer.gd`): uses the gravity vector (accelerometer fallback), not the raw gyroscope. Roll = atan2(g.x, -g.y) in screen space, calibrated neutral, dead zone, sensitivity, smoothing, flat-phone guard. Sensors are enabled in `project.godot`. Settings > Controls has toggle, sensitivity, dead zone, invert, calibrate and a live bar. In-game TILT / CAL buttons. Neutral is re-captured at session start and on every resume.
- **Day/night**: sun + clear blue sky by day; moon, stars and black sky at night (game starts at 09:00).
- **Vehicles**: wheels now visible on both faces and no longer buried in narrow bodies; lamps seated in bezels; rear valance, tucked exhausts, mirror stalks, thinner door seams.
- Needs on-device testing: real sensor sign/feel on Tecno Spark 7, performance on device.

## Visual Overhaul (this release)
- **Vehicles** – Kestrel R (red GT coupe), Hauler R (black pickup), Vela GT (white sports coupe), Brawler 69 (blue muscle car) use the new `scripts/vehicles/hero_cars.gd` builder: shoulder-line body shell, separate glasshouse/roof/pillars, wheel arches, per-car lamps, grilles, bumpers, exhausts and wing. All customization options (paint, tint, rims, bumper, body kit, spoiler, underglow, plate, headlights) still apply. Default paints: red / black / white / blue.
- **HUD** – round speedometer with rev arc, fuel + damage bars with icons, pedal-style BRAKE/GAS, two icon button columns, tilt slider, minimap, pause, money/time.
- **Collisions** – colliders for lamp poles, palms, trees, rocks, cacti and traffic-light poles; continuous collision detection; severity-based damage, dents, smoke, cracked glass, broken headlights.
- **Driving** – progressive throttle/brake response on top of the existing speed-sensitive steering, gearbox, downforce and anti-roll.
- **Environment** – lighter daytime haze.
- Tests: `tests/crash_test.tscn`, `tests/physics_test.tscn`, `tests/car_close.tscn`.

## Imported vehicles (GLB) – BMW M6 1988
- `assets/vehicles/bmw_m6_1988_custom.glb` is the starting/primary car (`bmw_m6` in `Data.VEHICLES`, `START_VEHICLE`). Older saves are granted it automatically.
- `scripts/vehicles/vehicle_models.gd` is the registry: one entry per GLB (scale, wheel seeds, lamps, glass, collision boxes, camera tweak, engine sound). `scripts/vehicles/glb_vehicle.gd` bakes the ~300 model pieces into one body mesh + 4 wheel meshes (cached), re-paints the body-red texels (`shaders/glb_body.gdshader`, also dents/wear) and returns the usual model dictionary.
- Wheels are parented to the existing `VehicleWheel3D` nodes, so the original controller steers/spins them. Collision uses simple boxes (body, front/rear bumper, cabin).
- Add another car: put the .glb in `assets/vehicles/`, add a registry entry + a `Data.VEHICLES` entry with the same id.
- Tests: `tests/glb_check.tscn` (bake/wheel/dimension check), `tests/glb_view.tscn`, `tests/crash_test.tscn -- bmw_m6`; in-game `--cmd=wheel_report`.

## World Expansion (traffic-pack cars, petrol station, buildings)
- 13 cars from `traffic_rider_npc_vehicles.glb` -> `assets/vehicles/pack/` (config: `tools/gen_pack_vehicles.py` -> `scripts/vehicles/pack_vehicles.gd`; each has its own price, handling, tank litres). Originals kept in `assets/vehicles/traffic_pack/`.
- Petrol station at city block (3,4): `scripts/world/gas_station.gd`, model `assets/locations/gas_station_opt.glb` (optimised by `tools/optimize_gas_station.py`; original kept). Zones: fuel pumps (`RefuelUI`), repair bay (`RepairUI`), dealership entrance (existing DealershipUI, now with fuel capacity, owned/available, confirm step, insufficient-funds message).
- Buildings from both packs: `tools/extract_buildings.py` -> `assets/buildings/pack/`, placed by `scripts/world/pack_district.gd` (no shadows, distance culled, box colliders).
- Prices: `FUEL_PRICE` / `repair_fee()` in `world.gd`; vehicle prices/specs in `tools/gen_pack_vehicles.py`.
- Build the APK with the existing GitHub Actions workflow (no local Android SDK).
