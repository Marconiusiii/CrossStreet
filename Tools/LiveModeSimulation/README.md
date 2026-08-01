# Live Mode Fetch Simulation

This is a standalone analysis tool, not part of the Intersector app target. It does not import app code and nothing in the app depends on it.

It answers one question: if Live Mode asked for map data continuously while a user walks, rides a bus, or rides in a car, how many Overpass requests would that generate, and could the public Overpass endpoints carry it?

Run it from the repository root:

    Tools/LiveModeSimulation/run.sh

The findings and what they mean are written up in `Documentation/LiveMode.md`.

## The Files

`CachePolicy.swift` is a copy of `MapDataCache` from `crossStreet/MapDataClient.swift`, with one deliberate change: every place the original reads the clock with `Date()`, this copy takes the time as a parameter. That is what makes it possible to replay a twenty-minute trip in a fraction of a second. All of the actual policy is reproduced unchanged — the reuse distance, both time-to-live values, the entry limit, the eviction order, and both branches of the `sameArea` coverage test.

Because this is a copy rather than the real type, it can drift. If the cache constants or the `sameArea` logic in `MapDataClient.swift` ever change, change them here too — otherwise this keeps printing confident numbers that no longer describe the app.

`Traces.swift` generates synthetic GPS traces: a stationary control, a walk, a stop-and-go bus, and a car on an arterial. Each trace carries GPS jitter, which matters because noise is what pushes a coordinate across a reuse boundary and causes a fetch that a clean path would not.

The jitter uses a fixed seed, so every run produces identical numbers. Any change in the output is a real change in behavior, not noise.

`main.swift` defines the candidate request policies, replays each trace through the cache under each policy, and prints the results.

## Changing Things

To try a different cache configuration, edit the `CacheTuning` values in `CachePolicy.swift` or add a new `LiveModePolicy` in `main.swift`. The existing policies show the pattern.

To add a trace, add a static function to `TraceLibrary` and include it in the `traces` array in `main.swift`.

## What It Does Not Model

Only the cache decision is simulated, not the network request itself. The tool says nothing about how long an Overpass query takes under load, which is a separate and equally important question for Car mode — a request that takes eight seconds is useless at speed no matter how few of them are needed.

There is also no in-flight request coalescing here, because the simulation is synchronous and never has two requests outstanding at once. On a real device, coalescing can only reduce the fetch count further, so these numbers are a ceiling rather than an underestimate.
