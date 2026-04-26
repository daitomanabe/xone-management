# Xone:K2 OSC LED Bridge

Native macOS bridge for driving Allen & Heath Xone:K2 A-P LEDs from Ableton
Live / Max for Live. This repository contains the Swift native implementation
and the Max for Live device only.

The system has two parts:

- `apps/Xone K2 OSC LED Bridge.app`: menu bar app that starts/stops the bridge.
- `m4l/xone-k2-osc-sender.amxd`: Max for Live audio effect that sends audio
  levels and beat position over UDP/OSC.

The bridge itself is a Swift/CoreMIDI executable at `scripts/osc-led-bridge`.
It listens on `127.0.0.1:9123`, receives OSC, and sends MIDI notes to the K2.

## Quick Start

```bash
make build-native
make build-m4l
make start
```

Then load `m4l/xone-k2-osc-sender.amxd` on the Ableton Live audio track you
want to analyze.

To use the Finder app instead of the terminal, open:

```text
apps/Xone K2 OSC LED Bridge.app
```

The app appears in the menu bar as `K2 On` and provides:

- Start Bridge
- Stop Bridge
- All LEDs Off
- Quit

## Commands

```bash
make build-native    # Build native bridge, M4L generator, and .app bundle
make build-m4l       # Regenerate .maxpat and .amxd from the native generator
make list            # List MIDI inputs/outputs
make test            # Run K2 LED chase and meter test
make all-off         # Turn all K2 LEDs off
make start           # Start OSC listener and K2 LED bridge
```

Direct CLI usage:

```bash
scripts/osc-led-bridge start --midi "XONE:K2" --channel 15 --osc-port 9123
scripts/osc-led-bridge set A red
scripts/osc-led-bridge all-off
```

## LED Layout

```text
A B C D   low / mid / high / beat 1
E F G H   low / mid / high / beat 2
I J K L   low / mid / high / beat 3
M N O P   low / mid / high / beat 4
```

Meter columns are bottom-to-top:

- Low: `M I E A`
- Mid: `N J F B`
- High: `O K G C`
- Beat: `D H L P`

Meter colors are green, green, amber, red. Beat 1 is red; beats 2-4 are amber.

## OSC Input

The bridge accepts standard OSC packets:

```text
/xone/levels <low 0..1> <mid 0..1> <high 0..1>
/xone/level/low <value 0..1>
/xone/level/mid <value 0..1>
/xone/level/high <value 0..1>
/xone/beat <beat number or 1..4 step>
/xone/set <A-P> <red|amber|green|off>
/xone/clear
```

`/xone/beat` may be a running beat number from Live transport. The bridge maps
it to steps 1-4 internally.

## Max for Live

Generated files:

- `m4l/xone-k2-osc-sender.amxd`
- `m4l/xone-k2-osc-sender.maxpat`

The M4L patch avoids `oscformat` so it works in Max environments where that
object is not available. It sends messages with `prepend /xone/...` into
`udpsend 127.0.0.1 9123`.

If Live refuses the generated `.amxd`, open `m4l/xone-k2-osc-sender.maxpat` in
Max, then save it as a Max Audio Effect device.

## Source Layout

```text
native/osc-led-bridge/       Swift CoreMIDI UDP/OSC bridge
native/osc-led-bridge-app/   Swift menu bar app wrapper
native/build-m4l/            Swift .maxpat/.amxd generator
scripts/                     Built native executables
apps/                        Built macOS app bundle
m4l/                         Max for Live device and editable patch
```

## Requirements

- macOS
- Allen & Heath Xone:K2 connected over USB/CoreMIDI
- Ableton Live with Max for Live for the included `.amxd`
- Xcode command line tools for rebuilding Swift executables

Default settings:

- MIDI output match: `XONE:K2`
- MIDI channel: `15`
- OSC listen address: `127.0.0.1:9123`

Copyright (c) 2026 Daito Manabe

Released under the MIT License.
