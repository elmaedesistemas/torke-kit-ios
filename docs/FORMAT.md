# The `torke.run` format

A recorded run as JSON: every raw sample plus the result. TorkeKit for iOS and for Android
read and write the same file, so a run recorded on one platform can be analyzed on the
other, on a server, or in your own tools. File extension: `.torkerun.json`.

```json
{
  "format": "torke.run",
  "version": 1,
  "recordedAt": "2026-11-21T16:54:06Z",
  "device": "iPhone16,1",
  "app": "Torke 1.0",
  "motion": [
    { "t": 1203.51, "user": [0.02, -0.11, 0.04], "gravity": [0.0, -0.34, 0.94] }
  ],
  "gps": [
    { "t": 1203.8, "speed": 0.1, "speedAccuracy": 0.4,
      "latitude": 9.9412, "longitude": -84.2005, "horizontalAccuracy": 3.2 }
  ],
  "result": {
    "launchTime": 1205.52, "sixtyFeet": 2.21, "zeroTo100": 6.4,
    "eighthMile": 8.93, "eighthMileKmh": 128.4,
    "quarterMile": 13.86, "quarterMileKmh": 163.0,
    "topSpeedKmh": 168.2, "accelBias": 0.04, "trace": []
  }
}
```

| Field | Meaning |
| --- | --- |
| `format`, `version` | Always `"torke.run"`; version `1`. Readers reject newer versions. |
| `recordedAt` | ISO 8601, optional. |
| `device`, `app` | Free text, optional. |
| `motion[].t` | Seconds on a monotonic clock shared with `gps[].t` (iOS: `systemUptime`; Android: `elapsedRealtime`). |
| `motion[].user` | Acceleration without gravity, m/s², phone frame, `[x, y, z]`. |
| `motion[].gravity` | Gravity direction, phone frame, `[x, y, z]` (any length). |
| `gps[].speed`, `speedAccuracy` | m/s, one standard deviation. `speedAccuracy ≥ 50` means the fix has a position but no speed. |
| `gps[].latitude`, `longitude`, `horizontalAccuracy` | Degrees (WGS 84) and meters, optional. |
| `gps[].altitude` | Meters above sea level, optional (0.2). Used for the slope check. |
| `result` | Optional. Times in seconds, speeds in km/h. Distance times discount the 1-foot rollout. `trace` may be empty. `launchG` and `peakG` (0.2) are optional. |
| `interval` | Optional (0.2): a rolling or braking result, `{ "kind": "rolling" \| "braking", "fromKmh", "toKmh", "time", "distance", "peakG", "startTime" }`. |
| `weather` | Optional (0.2): `{ "temperatureC", "humidity", "pressureHpa" }`, station pressure. |
| `suspension` | Optional (0.2): `{ "kind": "fourLink" \| "ladderBar" \| "torqueArm", "unit": "inches" \| "centimeters", "wheelbase", "cgHeight", "points": { "upperRear": { "x", "y" }, … }, "notes" }`. |

Missing optional fields are left out, never written as `null`. Version 0.2 only adds optional
fields, so the format version stays 1 and 0.1 readers still read 0.2 files.

Reference files in `Fixtures/`, written by TorkeKit for iOS; both SDKs must read them and get
the same numbers:

- `demo-42.torkerun.json`: the simulated street car, times within half a millisecond.
- `launch.torkerun.json`: a launch with altitudes, weather and a 4-link.
- `braking.torkerun.json` and `rolling.torkerun.json`: intervals.
- `phase2-expected.json`: density altitude, correction, instant center, anti-squat, best holes,
  quality grade, slope, g-forces and power for those files.

## The `torke.validation` format (0.3)

A set of recorded runs with their timeslips, for `torke-validate`:

```json
{
  "format": "torke.validation",
  "version": 1,
  "targets": { "sixtyFeet": 0.10, "quarterMile": 0.15, "speedKmh": 3 },
  "runs": [
    { "run": "runs/first.torkerun.json", "label": "Run 1",
      "timeslip": { "sixtyFeet": 2.12, "threeThirtyFeet": 5.71, "eighthMile": 8.55, "eighthMileSpeed": 89.9,
                    "quarterMile": 12.91, "quarterMileSpeed": 114.2, "speedUnit": "mph", "reactionTime": 0.512 } }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `runs[].run` | Path to a `.torkerun.json`, relative to the set's file. |
| `runs[].timeslip` | Any of `sixtyFeet`, `threeThirtyFeet`, `eighthMile`, `eighthMileSpeed`, `thousandFeet`, `quarterMile`, `quarterMileSpeed`. Times in seconds from leaving the staging beam. |
| `speedUnit` | `"kmh"` (default) or `"mph"`, for the speeds of that timeslip. |
| `reactionTime`, `notes` | Informative, not compared. |
| `targets` | Optional: the allowed error per mark (seconds, and `speedKmh` for both trap speeds). Defaults: 60 ft 0.10, 330 ft 0.12, 1/8 0.12, 1000 ft 0.15, 1/4 0.15, speed 3. |

`Fixtures/validation.json` is the demo run against the timeslip of its exact physics, and
`validation-expected.json` the errors both SDKs must get.

## Geofences and timing lines (0.4)

```json
{ "kind": "circle", "name": "La Guácima", "center": { "latitude": 9.9412, "longitude": -84.2005 }, "radius": 400 }
{ "kind": "polygon", "name": "Paddock", "points": [{ "latitude": 9.94, "longitude": -84.20 }, …] }
{ "a": { "latitude": 9.9410, "longitude": -84.2010 }, "b": { "latitude": 9.9414, "longitude": -84.2010 }, "name": "Start/finish" }
```

The same JSON on iOS and Android, so an app can download its tracks from a server.
