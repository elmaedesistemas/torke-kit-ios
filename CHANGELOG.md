# Changelog

## 0.1.0 · 2026-11-21

First open release, the same as TorkeKit for Android 0.1.0.

- Engine: `AxisCalibration`, `SpeedFilter`, `RunAnalyzer`, `DemoRun`.
- `RunSession` with `RunSnapshot`, `RunEvent` and `RunSessionOptions`.
- Launch detection catches a launch that ramps up over a few tenths of a second; a bump while
  armed no longer disarms, rolling or creeping does.
- `torke.run` JSON (`TorkeRun`) with the reference fixture `Fixtures/demo-42.torkerun.json`.
- `RunDataProvider`, `RecordedRunProvider` and `SensorSample`.
- `TorkeKitSensors`: `PhoneSensorProvider` for iOS.
