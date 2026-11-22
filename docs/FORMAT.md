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
