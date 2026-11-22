# TorkeKit for iOS

Open-source drag racing timing with a phone: 60 ft, 1/8 mile, 1/4 mile, 0–100 km/h and trap
speeds from the accelerometer and the GPS, however the phone sits in its mount. Also rolling
and braking intervals, weather correction, power estimates, a quality grade for each run and
suspension geometry (4-link, ladder bar, torque arm).

It is the engine behind [Torke](https://torke.today), for anyone building timing apps,
dragstrip tools or car products. [TorkeKit for Android](https://github.com/elmaedesistemas/torke-kit-android)
has the same API, the same results and reads the same files.

> *En español:* TorkeKit mide piques con el teléfono (60 pies, 1/8, 1/4, 0 a 100 y
> velocidades) a partir del acelerómetro y el GPS. Es el motor de Torke, abierto para quien
> quiera construir apps de cronometraje, herramientas para pistas o productos para carros.

📖 **Documentation:** [developers.torke.today](https://developers.torke.today), in Spanish: guides, the full API with Swift and Kotlin side by side, and interactive labs for the session, weather and 4-link geometry.

| Product | What it has | Depends on |
| --- | --- | --- |
| `TorkeKit` | Engine, `RunSession`, `torke.run` format, `RecordedRunProvider`, `DemoRun` | Foundation only (iOS 17, macOS 14) |
| `TorkeKitSensors` | `PhoneSensorProvider` (CoreMotion + CoreLocation), `PhoneBarometer` | iOS |
| `torke-validate` | The validation command, for the Mac: `swift run torke-validate` | macOS |

## Install

Swift Package Manager: `https://github.com/elmaedesistemas/torke-kit-ios`, from `0.4.0`.
Tags have no `v`.

```swift
.package(url: "https://github.com/elmaedesistemas/torke-kit-ios", from: "0.4.0")
```

## Use

```swift
import TorkeKit
import TorkeKitSensors

let phone = PhoneSensorProvider()
await phone.requestPermission()

let session = RunSession()
session.start(with: phone)      // GPS preview: snapshot.speed, snapshot.location
session.arm()                   // recording; the timer starts by itself at launch

for await event in session.events() {
    switch event {
    case .armed: print("Ready. Launch when you want.")
    case .passed(let mark, let elapsed): print("\(mark) ≈ \(elapsed) s (live)")
    case .finished(let result): print("1/4 mile: \(result.quarterMile ?? 0) s")
    case .failed(let failure): print("No run: \(failure)")
    default: break
    }
}
```

- `session.snapshot` is `@Observable`: bind SwiftUI straight to it.
- The run finishes by itself past the quarter mile, when the driver lifts, or after 40 s.
  `session.finish()` ends it by hand; `session.cancel()` drops it.
- `session.snapshot.startLocation` is where the run launched. Decide on your server whether
  it counts (a dragstrip, a sanctioned event).
- Add `NSLocationWhenInUseUsageDescription` and `NSMotionUsageDescription` to Info.plist,
  and keep the screen on while recording (`UIApplication.shared.isIdleTimerDisabled = true`).

### Recorded runs

```swift
let run = session.recording(device: "iPhone16,1", app: "MyApp 1.0")
let data = try run.encoded()                 // the torke.run JSON
let back = try TorkeRun.decode(data)
let result = back.analyze()                  // the times again
await RunSession().run(with: RecordedRunProvider(back))
```

The format is documented in [docs/FORMAT.md](docs/FORMAT.md).

### More measurements

```swift
let r = run.analyze(stopDistance: 850)!          // read past the quarter
r.thousandFeet; r.halfMile; r.zeroTo60mph
r.time(fromKmh: 100, toKmh: 200)
r.launchG; r.peakG

session.arm(mode: .rolling(fromKmh: 60, toKmh: 130))   // or .braking(fromKmh: 100)
// … .intervalFinished(let interval): interval.time, interval.distance
```

### Weather, power and quality

```swift
let weather = Weather(temperatureC: 31, humidity: 70, pressureHpa: 910)
weather.densityAltitude                          // meters
let corrected = result.corrected(for: weather)   // SAE J1349
PowerEstimate.fromTrapSpeed(massKg: 1350, quarterMileKmh: result.quarterMileKmh!)
PowerEstimate.peakWheelHp(result, massKg: 1350)

let quality = run.quality()!                     // .good, .fair or .poor, with the issues
```

### Suspension geometry

Textbook side-view geometry for 4-link, ladder bar and torque arm: instant center, anti-squat
and bar angles. Target windows are yours: TorkeKit ships no one's values.

```swift
let setup = SuspensionSetup.fourLink(
    wheelbase: 106, cgHeight: 21,
    upperRear: Point2(x: 4, y: 21), upperFront: Point2(x: 30, y: 23),
    lowerRear: Point2(x: 2, y: 9), lowerFront: Point2(x: 32, y: 12)
)
let g = setup.geometry()                         // g.icLength, g.icHeight, g.antiSquat, g.warnings

let target = TargetWindow(icLength: ValueRange(60, 75), icHeight: ValueRange(8, 12), antiSquat: ValueRange(80, 110))
let best = holes.ranked(base: setup, target: target).first   // which holes to try
let change = SetupChange(from: before, to: after)            // to read next to the 60 ft
```

`x` is forward of the rear axle centerline, `y` up from the ground, in inches or centimeters.

### Track tools

A Christmas tree on the screen with the reaction time from the stage beam, a lap timer for road
courses with sectors and a live delta, and geofences to decide where a run counts.

```swift
// Christmas tree: schedule the lights when the car is armed, measure the reaction after
let tree = ChristmasTree.start(type: .pro, stagedAt: ProcessInfo.processInfo.systemUptime)
tree.lights                                   // amber1…3 and green, on the samples' clock
result.reaction(on: tree)                     // .time (negative: red light), .isPerfect

// Lap timer: feed it every GPS fix
let timer = LapTimer(start: TimingLine(a: edgeA, b: edgeB), sectors: [split1, split2])
for event in timer.process(fix) { /* .started, .sector, .lap */ }
timer.delta; timer.predictedLap; timer.bestLap

// Geofences: where the run counts
let strip = Geofence.circle(center: Coordinate(latitude: 9.9412, longitude: -84.2005), radius: 400)
run.check(strip)                              // startInside, shareInside, allInside
```

### Validation against timeslips

How far TorkeKit is from the track's timer: each run is analyzed again and compared, mark by mark,
with its timeslip. Many runs give the bias, the typical error (RMS) and the worst case per mark.

```swift
let slip = Timeslip(sixtyFeet: 2.12, quarterMile: 12.91, quarterMileSpeed: 114.2, speedUnit: .mph)
let comparison = run.compare(with: slip)          // measured, reference and error per mark
let report = ValidationReport([("Run 1", run.analyze(), slip)])
report.summaries                                  // bias, meanAbsolute, rms, worst, passed
```

The same from the terminal, with a `torke.validation` JSON listing runs and timeslips
(see `Fixtures/validation.json`):

```bash
swift run torke-validate Fixtures/validation.json --runs
swift run torke-validate my-run.torkerun.json --60ft 2.12 --1/4 12.91 --1/4-speed 114.2 --mph
```

It exits with 0 when every mark is within its target (60 ft ±0.10 s, 1/4 mile ±0.15 s, trap speed
±3 km/h), so it fits in CI.

### The phone's GPS and barometer

- `session.snapshot.gpsRate` is how many fixes per second the GPS really gives: 1 on iPhone.
- `PhoneBarometer().stationPressureHpa()` reads the station pressure for `Weather`.

TorkeKit is phone-only by design: no external receivers or other hardware.

### Without a car

`RecordedRunProvider.demo()` plays a simulated street car (2 s still, then past the quarter
mile) with a tilted phone, sensor noise and a 1 Hz GPS. The same seed gives the same run on
iOS and Android.

## Accuracy

The tests simulate runs with exact physics and check the targets: ±0.15 s on the 1/4 mile,
±0.10 s on 60 ft and ±0.20 s on 0–100 km/h, with a 1 Hz phone GPS, sensor noise and a tilted
mount. A faster GPS improves the quarter. To check it against real runs, use
[`torke-validate`](#validation-against-timeslips) with your timeslips.

## How it works

1. `AxisCalibration` keeps the horizontal part of the acceleration and learns "forward" from
   the first strong push: the launch.
2. `SpeedFilter`, a two-state Kalman filter, predicts the speed from the accelerometer at
   100 Hz and corrects it, and the mount's bias, with the GPS.
3. `RunAnalyzer` finds the launch (one second still, then sustained acceleration), builds the
   speed and distance curve and reads the marks, discounting the 1-foot rollout.

## Development

```bash
swift test
TORKE_WRITE_FIXTURE=1 swift test --filter testWriteFixture   # regenerate the fixture
```

A change to the engine must keep `Fixtures/demo-42.torkerun.json` passing on both platforms.

## License

Apache 2.0. See [LICENSE](LICENSE).
