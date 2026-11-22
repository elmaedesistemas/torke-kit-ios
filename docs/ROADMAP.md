# Roadmap

## 0.1 · Phase 1: the open core (done)
- Engine: axis calibration, speed filter (accelerometer + GPS), run analyzer.
- `RunSession`: standstill, launch and finish detection, live snapshot and events.
- `torke.run` format, shared by iOS and Android, with a reference fixture.
- `RecordedRunProvider` and `DemoRun` for tests and demos.
- Phone sensor providers for iOS (CoreMotion, CoreLocation) and Android (SensorManager, LocationManager).

## 0.2 · Phase 2: more measurements and suspension geometry (done)
- Marks: 0–60 mph, 100–200 km/h, 1000 ft, 1/2 mile, custom distances.
- Rolling starts (for example 60–130 km/h) and braking (100–0).
- Launch g and peak g.
- Weather correction (temperature, humidity, pressure; SAE J1349).
- Power estimate from the trace and the vehicle's weight.
- Run quality: slope, GPS accuracy, dropouts, phone moving in the mount; a confidence grade per run.
- **Suspension geometry**, written from the textbook physics:
  - 4-link (equal length and short upper), ladder bar and torque arm.
  - Instant center (length and height), anti-squat with the center of gravity as an input, bar angles.
  - Hole changes: what happens to the instant center if a bracket moves.
  - Target windows as configuration: the SDK ships no one's values.
  - Measurements in inches or centimeters, as JSON shared by iOS and Android.
  - Link a setup to runs, so a change can be compared with its 60-foot time.

Left for later: instant center migration through suspension travel, and the setup's effect on
runs learned from many cars.

## Phase 3: external GPS and validation
- External GPS over Bluetooth (10–25 Hz receivers).
- `torke-validate`: compare SDK times with dragstrip timeslips or a reference GPS logger.

## Phase 4: track tools and docs
- Christmas tree engine (Pro .400, Sportsman .500), reaction time and red light.
- Lap timer for circuits: start/finish line, sectors, predicted lap.
- Geofences for tracks and events.
- Documentation site in Spanish, English and Portuguese.

Not planned for the SDK: leaderboard verification and anti-cheat checks stay on each
product's server.
