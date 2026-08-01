# Live Mode Design And Fetch Findings

This document describes a proposed Live Mode for Intersector, and records the results of a simulation that measured what Live Mode would cost in Overpass requests.

Live Mode is the feature where you turn the mode on, put the phone in your pocket, and hear intersections announced as you approach them, the way a driving GPS app calls out turns. It also covers a faster Car mode for riding a bus or a rideshare.

Nothing in this document has been built yet. The simulation described in the second half has been built and run, and lives in `Tools/LiveModeSimulation/`.

## Why Point And Scan Is Not Enough

Point and Scan was designed for standing still and sweeping the phone around to discover what is nearby. It does that well, and the design reflects it.

Look at `PointScanController.swift`. When a scan starts, it takes one location fix and stores it as `initialContext`. It fetches map data around that point. From then on it only listens to compass heading changes, and every heading update reuses that same original coordinate.

That is exactly right for a stationary user. It is also exactly why users report that it does not work on a bus. Ten minutes into a ride, the app is still reasoning about the intersections near the stop where the user boarded. The coordinate never moves.

Live Mode needs the opposite shape: a coordinate that updates continuously, and announcements driven by approaching an intersection rather than by pointing at one.

## The Four Things That Have To Change

### Background Location

Today the app declares only when-in-use location permission, and no background modes at all. When the screen locks, everything stops.

Live Mode needs always-authorization plus the location background mode, and `allowsBackgroundLocationUpdates` set on the location manager. Apple grants this for apps that genuinely provide turn-by-turn style guidance, but App Review will ask what it is for, so the permission strings need to say plainly that Live Mode is the reason.

One useful detail: iOS keeps an app alive indefinitely while location updates are flowing in background mode. There is no need for the audio background mode to stay alive, and no need for silent-audio tricks. Location alone is enough.

The background location indicator should be enabled so the system status bar discloses that location is in use.

### Speech That Does Not Depend On VoiceOver

This is the change with the most design consequence.

`VoiceOverAnnouncer.swift` posts an `AccessibilityNotification.Announcement`. That routes through VoiceOver, and it only works when the app is frontmost. Lock the phone and the announcements disappear. There is no speech synthesizer anywhere in the project today.

`AVSpeechSynthesizer` does work with the phone locked. The audio session needs to be configured for playback with ducking so that a podcast gets quieter rather than stopping.

The subtle part is choosing between the two channels. When VoiceOver is running and the app is in the foreground, accessibility announcements are better, because they follow the user's configured voice, speech rate, and audio routing — settings that blind users tune carefully and expect to be respected. When the app is backgrounded or the screen is locked, the synthesizer is the only option.

The approach that avoids trouble is a single announcer type that picks a channel based on scene phase and whether VoiceOver is running, so nothing is ever spoken twice through two channels at once. Everything in Live Mode routes through that one place.

### Predicting Instead Of Describing

Every report the app produces today answers the question "what is around me." Live Mode has to answer "what am I about to reach." That is a different question and it needs different logic.

The inputs are already being captured. `LocationProvider.context(from:)` already records course, course accuracy, and speed on every `DeviceContext`, and `DeviceContext.dependableTravelDirection` already decides when course is trustworthy enough to prefer over compass heading. Live Mode uses those rather than ignoring them.

The logic becomes: project the travel vector forward, find intersections along it, and announce at a time-to-arrival threshold rather than a distance threshold.

Using time rather than distance is what lets one engine serve both Walk and Car mode. Walking, an announcement around thirty seconds out gives useful warning. At thirty miles an hour, thirty seconds is a quarter mile, which is still the right amount of warning at that speed. The same rule produces sensible spacing at both speeds without a separate code path.

Two guards are needed on top. A hard minimum interval between announcements, so that a dense grid does not produce a machine-gun of street names. And a suppression rule so an already-announced intersection does not repeat. `PointScanController` already has a cooldown table doing this job, and the same idea carries over.

Car mode should also use a different report shape: less relative direction and precise distance, more a running commentary of what is being crossed. `OrientReport` already has a `kind` discriminator and assembles its text from preferences, so new kinds fit the existing pattern rather than fighting it.

Mode selection can be automatic from speed, with a manual override. Sustained speed above roughly fifteen miles an hour indicates a vehicle. The override matters because a bus in heavy traffic can sit below that threshold for a long time.

### Fetching Map Data Ahead Of Travel

This is where the simulation found the real problem, and it is covered in detail below.

## What The Simulation Measured

The concern going in was that Live Mode would generate far more Overpass traffic than the current tap-to-ask model, and that the public Overpass endpoints could not carry it. The simulation was built to replace guessing with a number.

### How It Works

The simulation lives in `Tools/LiveModeSimulation/`. It is three Swift files and a build script, standalone from the app target, and it does not touch app source.

`CachePolicy.swift` is a copy of `MapDataCache` from `MapDataClient.swift` with one change: every place the original calls `Date()`, the copy takes the time as a parameter. That is what allows a twenty-minute trip to replay in a fraction of a second. Every actual rule is reproduced unchanged — the 150 metre reuse distance, the 300 second fresh time-to-live, the 900 second stale time-to-live, the four-entry limit, the newest-first eviction order, and both branches of the `sameArea` coverage test.

`Traces.swift` generates synthetic GPS traces: a stationary control, a walk, a stop-and-go bus, and a car on an arterial. Each trace carries realistic GPS jitter, because noise is precisely what nudges a coordinate across a reuse boundary and causes a fetch that a clean path would not.

`main.swift` replays each trace through the cache under four different request policies and counts how many requests reach the network.

### Two Traps In Simulated GPS Data

Both of these produced believable but wrong numbers on the first run. They are easy to hit again in any work that replays location traces, so they are worth remembering.

The first run reported the stationary trace as having travelled 2.1 kilometres. The distance was being computed by summing the gaps between consecutive jittered fixes, which counts GPS wander as real movement. At one fix per second with five metres of noise, that manufactures kilometres of travel for someone standing still. Distance is now integrated from reported speed instead.

The same run showed the prefetch policy firing six fetches while standing at a corner, which made no sense. The cause was that the prefetch direction came from the bearing between consecutive fixes. Standing still, those bearings are pure noise, so the prefetch centre was being thrown 600 metres in a random direction on every evaluation. Real `CLLocation` reports an invalid course when stationary, and `DeviceContext` already discards it. The simulation now gates prefetch on actual speed, matching what the app already does.

### Results

Fetch counts are for one user on one trip.

Standing still costs one fetch under every policy. The cache handles the stationary case correctly, which is unsurprising because that is the case it was tuned for.

Walking fifteen minutes costs eight or nine fetches — roughly one every two minutes. The existing cache handles a walk without any modification at all.

A twenty-minute stop-and-go bus ride costs 31 fetches, about 1.6 per minute.

A twenty-minute car ride at thirty miles an hour costs 103 fetches, about one every twelve seconds. That is not a viable pattern against shared public infrastructure.

### The Structural Finding

The most useful result was a negative one: the obvious fixes do not work.

Throttling how often Live Mode consults the cache, from once a second to once every five seconds, takes the car trip from 103 fetches to 81. A modest gain.

Widening the request radius from 450 metres to 1200 metres, and tripling the cache time-to-live, changes the car trip not at all. Still 81 fetches.

The reason is the second branch of `sameArea` in `MapDataClient.swift`. A cached entry can be reused when the requested circle sits entirely inside the cached one, or when the radii match and the two centres are within 150 metres of each other. In practice the second branch is the one doing the work, because Live Mode asks with a consistent radius.

That means reuse is anchored on how close the request centre is to the cached centre, not on whether the cached data actually covers the requested area. When the request is re-centred on the user's current position every time, the user leaves the 150 metre centre window just as quickly with a large radius as with a small one. The larger circle gets fetched and then discarded without its extra coverage ever being used.

The fix follows directly: change where the app asks, not how much it asks for.

Corridor prefetch holds the request centre fixed until the user has travelled a set distance from it, then re-centres ahead along the direction of travel. With a 1200 metre radius, a 600 metre travel threshold, and a 600 metre lead, the bus trip drops from 31 fetches to 5, and the car trip drops from 103 to 14. Roughly a six to sevenfold reduction on both.

That reduction is also a battery saving, because each avoided fetch is an avoided cellular radio wake-up.

### Fleet Projection

Public Overpass instances are commonly documented as tolerating on the order of 10,000 queries per day from one source. Because all of the app's traffic shares one apparent source, that is a whole-app ceiling rather than per-user headroom.

Assuming one thirty-minute session per active user per day, measured against the bus profile:

With the naive policy, the app exceeds public fair use somewhere between 100 and 500 users. With corridor prefetch, it stays within fair use up to about 1,000 users and exceeds it before 5,000.

One session per user per day is a conservative assumption. A daily commuter runs two.

### What The Simulation Does Not Cover

It models the cache decision, not the network request. It says nothing about how long an Overpass request actually takes under load.

That matters independently. A fetch that takes eight seconds is useless at thirty miles an hour no matter how few of them are needed. Measuring that requires real requests against a real endpoint, and has not been done.

## Conclusions

Walking Live Mode can ship on the existing infrastructure. This was not obvious before the simulation, and it means the walking feature does not have to wait for a server.

Car mode cannot ship on public Overpass. Even with prefetch it is the heaviest profile, and it is the one that transit users are asking for.

Corridor prefetch is worth building regardless of which data backend is chosen, both for the request reduction and for the battery saving.

The case for offline map packs is strengthened rather than weakened. Prefetch buys roughly one order of magnitude. Growing from 1,000 users to 10,000 needs another one. Offline packs take the per-session request count to zero, and additionally make Live Mode work in a subway tunnel or a dead zone — which for a blind user on transit is the difference between a tool that can be relied on and one that goes silent at the worst moment.

## Battery Notes

Continuous GPS is the dominant cost and is roughly what any turn-by-turn app spends. Several things reduce it without hurting the experience.

Walking mode does not need `kCLLocationAccuracyBest`. Nearest-ten-metres is ample for intersection proximity and is meaningfully cheaper. A distance filter of around ten metres cuts wake-ups substantially compared to processing every fix.

The compass should not run continuously in Car mode. GPS course is more reliable than magnetometer heading in a moving vehicle anyway, because the metal body interferes with the magnetometer. In walking mode heading is useful, but only near an intersection rather than for the whole session.

A session timer or an automatic stop after a long stationary period prevents a forgotten Live Mode from draining the battery overnight.

The mode must be obviously and easily stoppable — a prominent in-app control, and ideally a lock screen presence.

## Suggested Build Order

1. Extend `LocationProvider` with a continuous location stream alongside the existing one-shot API, without disturbing Point and Scan.
2. Build the dual-channel announcer and confirm speech actually works with the screen locked. Everything else depends on that assumption holding.
3. Build the predictive engine with walking thresholds.
4. Implement corridor prefetch and rework the cache for a moving user.
5. Add Car mode as a threshold and report-shape variation on the working engine.
6. Add Siri intents for starting and stopping Live Mode, and a Live Activity for lock screen status.
7. Investigate offline map packs.

The riskiest unknowns are Overpass latency under load and how the VoiceOver-to-synthesizer handoff feels in practice. Both are worth prototyping roughly before committing to the full build.

## Running The Simulation

From the repository root:

    Tools/LiveModeSimulation/run.sh

The script compiles the three Swift files and runs the result. It prints a table per trace showing evaluations, fetches, cache hits, and fetch rate under each policy, followed by the fleet projection.

The traces use a fixed random seed, so the numbers are identical on every run and on every machine. Changing the tuning constants in `CachePolicy.swift` or the policies in `main.swift` is the intended way to explore alternatives.
