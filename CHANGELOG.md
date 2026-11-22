# Changelog

## 0.3.0 · 2026-11-22

Validation against timeslips and the most from the phone's GPS. Same results as TorkeKit for Android 0.3.0,
checked with shared fixtures (`validation.json`, `validation-expected.json`).

- `torke-validate`: `Timeslip`, `RunComparison`, `ValidationReport` (bias, mean absolute error, RMS and
  worst case per mark, against `ValidationTargets`), `TorkeRun.compare(with:)` and the `torke.validation`
  JSON (`ValidationSet`). The `torke-validate` executable: `swift run torke-validate --help`.
- `DragDistance.threeThirtyFeet` (330 ft).
- `RunSnapshot.gpsRate`: GPS fixes per second over the last 5 s.
- `TorkeKitSensors`: `PhoneBarometer` for the station pressure.

## 0.2.0 · 2026-11-21

More measurements, run quality and suspension geometry. Same results as TorkeKit for Android 0.2.0,
checked with shared fixtures.

- Marks: `elapsed(toDistance:)`, `speedKmh(atDistance:)`, `time(toKmh:)`, `time(fromKmh:toKmh:)`,
  `zeroTo60mph`, `thousandFeet`, `halfMile`. `RunAnalyzer.analyze(…, stopDistance:)` reads past the 1/4.
- `RunResult.launchG` and `peakG`.
- Rolling and braking: `IntervalAnalyzer`, `IntervalResult`, `RunSession.arm(mode:)` with `.rolling`
  and `.braking`, the `.intervalFinished` event and `RunFailure.noInterval`.
  `AxisCalibration.forwardAccel(_:orientedBy:)` checks "forward" against the GPS.
- `Weather`: air density, density altitude, SAE J1349 correction; `RunResult.corrected(for:)`.
- `PowerEstimate`: Hale from trap speed and from ET, wheel power along the run.
- `RunQuality`: GPS rate, accuracy and dropouts, slope from GPS altitude, loose mount, phone moving,
  sensors against GPS; graded good, fair or poor.
- Suspension: `SuspensionSetup` (4-link, ladder bar, torque arm), `SuspensionGeometry` (instant center,
  anti-squat, bar angles, warnings), `TargetWindow`, `FourLinkHoles` and `SetupChange`.
- `GPSSample.altitude`; `TorkeRun.interval`, `weather` and `suspension`. Optional fields: format version 1.
- `PhoneSensorProvider` sends the GPS altitude.

## 0.1.0 · 2026-11-21

First open release, the same as TorkeKit for Android 0.1.0.

- Engine: `AxisCalibration`, `SpeedFilter`, `RunAnalyzer`, `DemoRun`.
- `RunSession` with `RunSnapshot`, `RunEvent` and `RunSessionOptions`.
- Launch detection catches a launch that ramps up over a few tenths of a second; a bump while
  armed no longer disarms, rolling or creeping does.
- `torke.run` JSON (`TorkeRun`) with the reference fixture `Fixtures/demo-42.torkerun.json`.
- `RunDataProvider`, `RecordedRunProvider` and `SensorSample`.
- `TorkeKitSensors`: `PhoneSensorProvider` for iOS.
