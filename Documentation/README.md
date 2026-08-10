# Intersector Code Guide

This guide explains how Intersector is built. It is written as a plain-language code tour, so you can connect the app behavior to the Swift files that make it work.

The main idea to keep in mind is this:

1. The UI asks for a piece of orientation information.
2. The app gets location and sometimes heading data.
3. The app fetches nearby street data.
4. The app turns that map data into intersection candidates.
5. The app chooses the best candidate for the requested action.
6. The app optionally looks up nearby neighborhood context.
7. The app turns that result into text and updates the screen.

## Project Map

These are the most important files:

- `crossStreetApp.swift`
  Starts the app and registers App Shortcuts.

- `ContentView.swift`
  Builds the main screen, settings sheet, action buttons, and current status text.

- `OnboardingView.swift`
  Shows the first-run onboarding flow and requests location permission.

- `AppPrefs.swift`
  Defines app settings such as neighborhood context, map detail, intersection wording, measurement unit, direction style, announcement content, and haptic feedback.

- `LocationProvider.swift`
  Wraps CoreLocation so the rest of the app can ask for location and heading data with async functions.

- `OrientSvc.swift`
  Coordinates the main intersection report flow.

- `MapDataClient.swift`
  Talks to Overpass, decodes OpenStreetMap data, builds map models, and caches results.

- `NeighborhoodProvider.swift`
  Looks up nearby named places from OpenStreetMap so report text can include neighborhood context.

- `IntersectionFinder.swift`
  Chooses the nearest, upcoming, or pointed-at intersection from a list of candidates.

- `OrientationReport.swift`
  Defines the app's report models and converts a report into readable text.

- `PointScanController.swift`
  Runs Scan Mode, including warmup state, heading updates, cooldowns, haptics, and announcements.

- `CrossStreetIntents.swift`
  Defines Siri and Shortcuts actions using App Intents.

- `IntersectorWatch/`
  Contains the Apple Watch companion app target. The first watch pass provides one-shot Nearest and Upcoming reports through a small watch UI and watch App Intents.

- `VoiceOverAnnouncer.swift`
  Sends system accessibility announcements when the current information changes.

- `HapticFeedback.swift`
  Centralizes haptic feedback calls.

- `MailComposerView.swift`
  Wraps the UIKit mail composer so SwiftUI can present it.

## How The App Starts

The app starts in `crossStreetApp.swift`.

`IntersectorApp` is marked with `@main`, which tells Swift that this is the app entry point. Its `body` creates a `WindowGroup` and puts `ContentView()` inside it.

The app initializer calls:

```swift
IntersectorShortcuts.updateAppShortcutParameters()
```

That tells the system to refresh the App Shortcut phrases defined in `CrossStreetIntents.swift`.

The useful pattern here is:

- Put app-level setup in the `App` type.
- Put screen-level behavior in views or view models.
- Keep the entry point small.

## Main Screen Structure

The main screen lives in `ContentView.swift`.

`ContentView` decides whether to show onboarding or the main app:

```swift
if hasCompletedOnboarding {
	mainView
} else {
	OnboardingView(...)
}
```

The value comes from:

```swift
@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
```

`@AppStorage` connects a Swift property to `UserDefaults`. It is useful for small persisted settings such as whether onboarding has completed.

The main screen has these parts:

1. Header
2. Current Info area
3. Nearest button
4. Upcoming button
5. Direction button
6. Scan toggle

The visible button labels are intentionally short so they hold up better with larger text sizes. Their accessibility labels still use the fuller action names, such as `Nearest Intersection`, `Upcoming Intersection`, `My Direction`, and `Scan Mode`.

Nearest and Upcoming can also show subtle chevron menu controls beside them. These menus give sighted and low-vision touch users access to 2nd and 3rd ranked results without adding four more full-width buttons. The menus are hidden from VoiceOver because the Nearest and Upcoming buttons already expose those same ranked choices as custom accessibility actions.

Scan Mode uses a stronger border because it starts and stops a live mode. When it is preparing or scanning, its background changes from yellow to orange so the active state is visible without relying only on the other buttons becoming disabled.

The main screen uses a vertical `ScrollView` for all text sizes.

Each major row has a scaled minimum height. The minimum height gives the row enough tappable space at normal text sizes, while still allowing the row to grow when Dynamic Type is larger.

This avoids a common SwiftUI problem: if you force large text into a fixed-height row, the text can look cut off or overlap nearby controls. Letting the content grow is usually the better accessibility-first layout pattern.

## State In ContentView

`ContentView` uses SwiftUI state properties to drive what the user sees:

```swift
@AppStorage("areaMode") private var areaModeRaw = AreaMode.near.rawValue
@AppStorage("measurementUnit") private var measurementUnitRaw = MeasurementUnit.feet.rawValue
@AppStorage("directionStyle") private var directionStyleRaw = DirectionStyle.words.rawValue
@AppStorage("intersectionWording") private var intersectionWordingRaw = IntersectionWording.direct.rawValue
@AppStorage("spokenIntersectionCount") private var spokenIntersectionCountRaw = SpokenIntersectionCount.one.rawValue
@AppStorage("includeAnnouncementDistance") private var includeAnnouncementDistance = true
@AppStorage("includeAnnouncementDirection") private var includeAnnouncementDirection = true
@AppStorage("includeAnnouncementNeighborhood") private var includeAnnouncementNeighborhood = false
@AppStorage("includeCrossings") private var includeCrossings = false
@AppStorage("includeWalkingPaths") private var includeWalkingPaths = false
@State private var statusText = "Choose an action."
@State private var isLoading = false
@State private var isDirectionLoading = false
@State private var isShowingSettings = false
@StateObject private var pointScanner = PointScanController()
```

Important patterns:

- `@AppStorage` stores simple settings in user defaults so they persist across app launches.
- `@State` stores simple view-owned values.
- `@StateObject` owns a reference-type object that should live as long as the view lives.
- Changing `@AppStorage`, `@State`, or `@StateObject` values causes SwiftUI to redraw the parts of the view that depend on them.

`ContentView` builds an `AppPrefs` value from the stored setting values when it needs to call the report service. That includes map detail settings, so the lookup code can tell whether crossings or walking paths should be included.

`statusText` is the main piece of screen text for results and errors. The existing text stays visible while a new command runs. A native indeterminate linear progress strip appears immediately below Current Info and remains visible until the command completes without becoming a separate VoiceOver element. The gold outline around Current Info follows the same active-command state. If an intersection lookup lasts about two seconds, a low-priority VoiceOver status announcement says that Intersector is still finding the intersection. If the lookup continues for another eight seconds, a second low-priority status announcement explains that it is still working.

When the result or error arrives, the progress strip and gold outline disappear and the new text replaces the old text with a short fade. Without Reduce Motion, the incoming text also moves upward by four points. With Reduce Motion, the transition uses only the fade. The completed result uses a high-priority VoiceOver announcement.

## What Happens When Nearest Intersection Is Pressed

The Nearest Intersection button calls:

```swift
await updateReport(.nearest)
```

`updateReport(_:)` does this:

1. Checks `isLoading` so two reports do not run at the same time.
2. Sets loading state.
3. Shows the progress strip and gold Current Info outline immediately without replacing the existing Current Info text.
4. Calls `OrientSvc.shared.spokenText(kind, prefs: prefs)`.
5. Sends low-priority status announcements only if the lookup takes long enough.
6. Cancels the delayed loading task when a result or error arrives.
7. Replaces `statusText` using the fade as the active progress strip and outline disappear.
8. Sends the completed result or error through `VoiceOverAnnouncer.reportUpdated(_:)`.
9. Clears loading state and hides the progress strip.

The code path is:

```text
ContentView
-> OrientSvc
-> LocationProvider
-> MapDataClient
-> IntersectionFinder
-> NeighborhoodProvider
-> OrientationReport
-> ContentView statusText
```

This is a good app architecture pattern: the button does not know how map data works. The button asks a service for a report.

## What Happens When Upcoming Intersection Is Pressed

The Upcoming Intersection button also calls `updateReport(_:)`, but with:

```swift
.upcoming
```

The shared service code is mostly the same, but the matching rule changes in `IntersectionFinder`.

For nearest, the app picks the closest candidate.

For upcoming, the app first identifies the named road nearest the user's location. It uses the phone heading only to choose which direction to travel along that road, then follows the connected road geometry through bends and separately mapped segments. Upcoming does not select intersections from a compass cone and does not fall back to a nearby intersection on another street. If the road or travel direction cannot be established confidently, the request returns no Upcoming result instead of guessing. If a fresh heading request times out, the location provider can retain a heading that is no more than two seconds old instead of immediately discarding useful direction data.

The useful pattern here is that `ReportKind` changes behavior without duplicating the whole lookup flow.

## The Report Service

`OrientSvc.swift` is the coordinator for the main report flow.

Its main method is:

```swift
func report(_ kind: ReportKind, prefs: AppPrefs = AppPrefs()) async throws -> OrientReport
```

It does the high-level work in order:

1. Ask `LocationProvider` for a `DeviceContext`.
2. Ask `MapDataClient` for nearby intersections and road geometry, expanding the radius only when more results are required.
3. Ask `IntersectionFinder` for the best match.
4. Calculate distance and bearing.
5. Convert bearing plus heading into a relative direction.
6. Ask for neighborhood context if the Settings value needs it.
7. Match the nearest road to the selected intersection when street-context wording is available.
8. Build an `OrientReport`, or build an ordered report list when the Spoken Intersections setting requests multiple results.

The report service passes the current map detail settings into `MapDataClient`. This matters because changing map detail changes what the app considers a candidate. For example, a named footpath should not appear in results unless the Walking Paths setting is turned on.

`DeviceContext` is defined in `OrientationReport.swift`:

```swift
struct DeviceContext: Equatable {
	var coordinate: CLLocationCoordinate2D
	var headingDegrees: CLLocationDirection?
	var courseDegrees: CLLocationDirection?
	var courseAccuracy: CLLocationDirection?
	var speedMetersPerSecond: CLLocationSpeed?
	var horizontalAccuracy: CLLocationAccuracy?
}
```

It keeps the user's coordinate and optional heading together. This is cleaner than passing latitude, longitude, and heading as separate loose values through the app.

## Protocols For Replaceable Services

`OrientSvc.swift` defines two protocols:

```swift
protocol LocationProviding {
	func currentContext() async throws -> DeviceContext
}

protocol MapDataFetching {
	func intersections(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> [IntersectionCandidate]
	func mapData(
		near coordinate: CLLocationCoordinate2D,
		radiusMeters: CLLocationDistance,
		options: MapDetailOptions
	) async throws -> MapDataSet
}

protocol NeighborhoodProviding {
	func neighborhoods(near coordinate: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) async throws -> [NeighborhoodCandidate]
}
```

Protocols define what a service can do without locking the app to one concrete implementation.

This matters because:

- `OrientSvc` can use the real `LocationProvider` in the app.
- Tests can provide fake location or map data if needed.
- The code is easier to reason about because each dependency has a small contract.

This is a common engineering pattern called dependency injection. In plain language, it means a type receives the helpers it needs instead of creating every helper internally.

## NeighborhoodProvider

`NeighborhoodProvider.swift` powers the Neighborhood context setting.

The Settings control is stored in:

```swift
AppPrefs.areaMode
```

The values are:

- `off`
- `near`
- `toward`

When the value is `off`, `OrientSvc` skips neighborhood lookup entirely.

When the value is `near` or `toward`, `OrientSvc` asks `NeighborhoodProvider` for named place data near the current coordinate. The neighborhood lookup is best-effort. If it fails, the app still returns the intersection report without neighborhood text.

That is an important engineering choice: neighborhood text improves the report, but it is not allowed to break the main result.

## Neighborhood Data

Neighborhood data comes from OpenStreetMap through Overpass, but it is queried separately from street intersection data.

`NeighborhoodProvider` asks for named place data such as:

- `place=neighbourhood`
- `place=quarter`
- `place=suburb`
- `place=locality`
- `boundary=place`
- selected administrative boundaries

The provider returns app-specific `NeighborhoodCandidate` values. Each candidate has:

- an ID
- a name
- a coordinate
- a kind

The kind has a priority. More specific place types, such as neighbourhood, are preferred over broader or less specific types.

## NeighborhoodResolver

`NeighborhoodResolver` chooses which neighborhood text should be used.

For `Nearby only`, it picks the best nearby candidate.

For `Nearby and toward`, it still finds the nearby candidate, but it also uses heading to find a candidate in the direction the device is facing.

The resulting values are stored in:

```swift
NeighborhoodContext(area: area, toward: toward)
```

Then `OrientSvc` copies those values into the final `OrientReport`.

`OrientationReport.text(with:)` already knows how to handle them:

- Nearby mode can produce text like `in Mission District`.
- Toward mode can produce text like `toward North Beach`.

This is a useful example of building a feature in layers. The report model and Settings control already existed, so the new work only had to provide real data for those fields.

## LocationProvider

`LocationProvider.swift` wraps `CLLocationManager`.

CoreLocation is delegate-based. That means iOS calls methods such as `locationManager(_:didUpdateLocations:)` when new data arrives.

The rest of this app uses async functions. `LocationProvider` is the bridge between those styles.

The main method is:

```swift
func currentContext() async throws -> DeviceContext
```

It:

1. Starts heading updates if heading is available.
2. Checks location authorization.
3. Reuses a recent accurate location if it has one.
4. Starts active location updates.
5. Waits for a good enough location.
6. Times out after a short window.
7. Returns the best usable location if ideal accuracy was not reached.

The key idea is that the app does not accept the first location blindly. It keeps track of:

- `latestLocation`
- `bestActiveLocation`
- ideal accuracy
- usable accuracy
- recent location age
- timeout

That gives the app a balance between speed and accuracy.

## Continuations

`LocationProvider` uses continuations:

```swift
CheckedContinuation<DeviceContext, Error>
```

A continuation is Swift's way of turning callback-style code into async code.

In plain language:

1. The async function starts.
2. It stores a continuation.
3. It starts CoreLocation.
4. Later, CoreLocation calls a delegate method.
5. The delegate method resumes the continuation with either success or failure.
6. The original async function continues.

This lets the rest of the app write:

```swift
let context = try await locationProvider.currentContext()
```

instead of manually handling CoreLocation delegates everywhere.

## Stopping Location Updates

When `LocationProvider` finishes a request, it calls:

```swift
manager.stopUpdatingLocation()
```

That matters because location updates can continue until stopped. Good app code starts expensive system work only when needed and stops it when the task is done.

Heading updates are handled similarly. Scan Mode keeps heading updates active while scanning. A one-shot fresh heading ignores invalid Core Location samples and briefly collects updates before using the latest value, which avoids treating the first intermediate reading during a quick phone movement as settled. If Upcoming still cannot align that heading with the loaded road geometry, it requests one more settled heading and reevaluates the same map data without forcing another network request. Other one-shot heading requests stop when they are finished if no stream still needs them.

## MapDataClient

`MapDataClient.swift` fetches OpenStreetMap data through Overpass.

The app asks for map data near a coordinate:

```swift
func mapData(
	near coordinate: CLLocationCoordinate2D,
	radiusMeters: CLLocationDistance,
	options: MapDetailOptions
) async throws -> MapDataSet
```

The flow is:

1. Ask `MapDataCache` if usable data already exists.
2. If cached data is available, return it.
3. If another matching request is already running, wait for it.
4. Otherwise, make a POST request to Overpass.
5. Decode the JSON.
6. Build app-specific map models.
7. Store the result in cache.

The cache stores the map detail options with each result. That keeps the app from reusing a simpler cached result after the user turns on extra map detail.

## The Overpass Query

The query asks for named street-like ways around the current coordinate. It can also ask for extra map details when the matching setting is turned on.

```text
way(around:radius,lat,lon)["highway"~"..."]["name"];
(._;>;);
out body;
```

Important pieces:

- `way` means OpenStreetMap road or path-like line data.
- `around` limits the query to a circle around the device.
- `highway` is the OpenStreetMap tag used for many road and path types.
- `name` means the app only asks for named ways.
- `(._;>;);` also asks for the nodes that make up those ways.

Standard street data is always included. Named walking paths are included from the first Upcoming lookup when Walking Paths is turned on, allowing Upcoming to follow a named park path and find its mapped junctions. The query deliberately requires names, so an unnamed path cannot produce a named intersection and is not used as a guessed result. Crossing nodes are included only when Crossings is turned on.

OpenStreetMap ways are made from nodes. A way might be a street, and each node is a point along that street. Intersections are found by looking for nodes shared by two or more named ways.

## JSON Decoding

Overpass returns JSON. The app decodes it into:

```swift
struct OverpassResponse: Decodable {
	var elements: [OverpassElement]
}
```

Each `OverpassElement` can be a node or a way.

The custom decoder handles tag values that may come back as different primitive types. It uses `FlexibleString` so the app can still treat tag values as strings.

That is a practical defensive coding pattern for external data. Even if the API usually returns one shape, the app avoids breaking when a value comes back as an integer, double, or boolean.

## Building Intersections From Map Data

`IntersectionBuilder` turns raw Overpass elements into `MapDataSet`.

It builds:

- A dictionary of node IDs to coordinates.
- A dictionary of node IDs to street names.
- A list of `MapRoad` values.
- A list of `IntersectionCandidate` values.

The important rule is:

```swift
guard names.count >= 2
```

If a node belongs to two or more named roads, the app treats that node as an intersection candidate.

The final candidate has:

- an ID
- the road names
- the coordinate

When crossings are enabled, a crossing node on one named road can also become a candidate. The app names that candidate with copy like `Crossing on Oak Street`. Crossing nodes within 30 meters of a true street intersection are suppressed so they do not create nearly identical ranked results.

## MapDataSet

`MapDataSet` stores both:

- `intersections`
- `roads`

The normal nearest and upcoming buttons mostly use `intersections`.

Scan Mode also needs `roads`, because it first finds the road closest to the current coordinate and then filters intersections to that road.

That method is:

```swift
currentStreetIntersections(from:)
```

It finds the nearest road by measuring from the user's coordinate to the full line segments between road nodes. Then it keeps only intersections whose road associations include that road name.

For Street Context wording, the same distance calculation is limited to the roads that form the selected intersection. A nearby unrelated road therefore cannot force the report back to Direct wording.

For Spoken Intersections values 2 and 3, Nearest Intersection ranks mapped candidates by distance. Upcoming Intersection follows only intersections connected along the detected current road. It orders them by cumulative distance traveled through the road geometry rather than straight-line distance. It never fills a missing position with an intersection from a nearby street.

Ranked one-shot requests, such as 2nd Nearest, 3rd Nearest, 2nd Upcoming, and 3rd Upcoming, are different from the Spoken Intersections setting. A ranked one-shot request speaks only the requested intersection. Ranked Upcoming begins with a small 225-meter discovery lookup. If that does not contain enough current-road intersections, one focused request fetches the detected road and the named roads connected to it, using 750 meters for the second rank or 1,200 meters for the third. This avoids repeated large circular queries across every named Manhattan street. The spoken lead includes the rank, such as `2nd Upcoming:` or `3rd Nearest:`.

## MapDataCache

`MapDataCache` is an `actor`.

Actors protect their stored state from being changed by multiple tasks at the same time. That is useful for a cache because several app actions could ask for map data close together.

The cache stores:

- recent successful map results
- a currently running request

It can:

- reuse fresh nearby data
- let matching callers share one in-flight request
- return stale nearby data if a fresh network request fails

This avoids unnecessary network calls and reduces how often a temporary map server problem becomes a visible app error.

## Endpoint Fallback

`MapDataClient` has one primary endpoint and two fallback endpoints. Requests identify Intersector with a `User-Agent`, use a practical network timeout, and remember temporarily unhealthy endpoints so the next request can prefer a working server.

If the primary endpoint fails with a temporary network or server problem, the client tries the fallback endpoint.

Temporary errors include examples like:

- timeout
- connection loss
- too many requests
- temporary server unavailable
- gateway timeout

Invalid map data is not treated as temporary. If the app cannot decode the response, retrying the same query on another endpoint may not fix it, so that error is allowed to surface.

## IntersectionFinder

`IntersectionFinder.swift` is pure matching logic. It does not know about SwiftUI, network requests, or CoreLocation permissions.

For nearest:

```swift
nearestCandidate(from:in:)
```

It compares the distance from the device coordinate to each candidate and picks the smallest.

For upcoming:

1. Match the user to a nearby named road.
2. Find the closest segment of that road.
3. Use the phone heading to choose a direction along the segment.
4. Traverse connected nodes carrying the same road name.
5. Order intersections by cumulative distance along that road path.
6. Return no result when the road or direction cannot be established confidently.

For scan:

1. Compare the phone heading to each candidate bearing.
2. Prefer the smallest angle difference.
3. If angle differences are close, prefer the nearer candidate.

This is a good example of keeping an algorithm isolated. You can test this file without launching the app or fetching map data.

## Geo Helpers

`Geo` lives in `OrientSvc.swift`.

It provides shared math and formatting:

- `distanceMeters`
- `bearingDegrees`
- `normalizedDegrees`
- `compassDirection`
- `spokenDistance`

The app uses meters internally because CoreLocation works in meters. It formats spoken distances in feet or miles for output.

The bearing math returns a compass degree from one coordinate to another. The app then turns that into a word such as north, northeast, or west.

## OrientationReport

`OrientationReport.swift` defines the output model.

`OrientReport` stores structured result data:

- report kind
- intersection name
- distance
- relative direction
- relative direction in degrees
- street
- compass heading
- area
- toward
- internal confidence level

Then `text(with:)` turns the structured data into one short sentence. It does not append a confidence sentence to each report, which keeps repeated announcements concise.

For example:

```text
Nearest: Oak Street and Pine Street, about 80 feet ahead in Downtown.
```

That separation is useful. The app can keep logic structured internally while still producing readable text at the end.

## ReportKind

`ReportKind` is an enum:

```swift
nonisolated enum ReportKind {
	case nearest
	case upcoming
	case scan
}
```

Enums are useful when a value can only be one of a small set of known cases.

Here, `ReportKind` lets the app pass one clear value through the system instead of passing strings such as `"nearest"` or `"upcoming"`.

That makes the compiler help you. If a new case is added later, Swift can point out places where the code needs to handle it.

## Scan Mode

`PointScanController.swift` is an `ObservableObject`.

It publishes:

```swift
@Published private(set) var isPreparing = false
@Published private(set) var isScanning = false
```

`ContentView` observes those values through `@StateObject`. When they change, the Scan Mode toggle state updates.

Starting Scan Mode does this:

1. Set preparing state.
2. Update the status text to loading.
3. Start preparation haptics if enabled.
4. Get the current location.
5. Fetch map data around that location.
6. Find intersections on the current street.
7. Set ready/scanning state.
8. Start listening to heading updates.

While scanning, each heading update is checked against nearby intersections. When the phone points close enough to an intersection, the controller builds a scan report, updates the screen, sends haptics if enabled, and announces the result.

## Long-Running Tasks

Scan Mode uses a stored task:

```swift
private var scanTask: Task<Void, Never>?
```

That task stays alive while scanning is active. When scanning stops, the task is cancelled.

This is a common Swift concurrency pattern:

- Store the task when work should continue over time.
- Cancel the task when the feature turns off.
- Check cancellation inside loops.

## AsyncStream For Heading Updates

`LocationProvider.headingUpdates()` returns:

```swift
AsyncStream<CLLocationDirection>
```

An `AsyncStream` lets code use a `for await` loop for values that arrive over time.

Scan Mode uses:

```swift
for await heading in locationProvider.headingUpdates()
```

That reads naturally: for every heading update, run the scan matching logic.

This is cleaner than making the scan controller itself a CoreLocation delegate.

## Cooldowns

Scan Mode stores:

```swift
private var spokenCooldowns: [String: Date] = [:]
```

That keeps track of when each intersection was last announced.

Before announcing again, it checks whether enough time has passed. This prevents the same intersection from being repeated too quickly while the phone remains pointed in the same direction.

The pattern is simple and useful:

- Use a dictionary keyed by stable ID.
- Store the last event time.
- Compare the current time to that stored time.

## Haptics

`HapticFeedback.swift` centralizes haptic calls.

Scan Mode uses haptics in two ways:

- preparation pulses while the mode is loading
- scan feedback when pointing near a candidate

Keeping haptic calls in one helper keeps platform-specific feedback code out of the matching logic.

## VoiceOverAnnouncer

The app uses `VoiceOverAnnouncer` when it needs the system to speak updated status text.

The important design is that the app updates visible text and sends the same text as an announcement.

That keeps the visible state and spoken state aligned.

Completed report announcements use high priority. Longer-loading status announcements use low priority so they do not repeatedly interrupt commands or compete with the final result. The app does not move VoiceOver focus away from the button that triggered the report, so users can keep pressing the same action button if they want repeated updates.

## Settings

Settings are built inside a SwiftUI `Form` in `ContentView.swift`.

The first item explains that intersection directions and distances are estimates based on location, device heading, and available map data. Keeping this information in Settings avoids repeating confidence wording in every visible and spoken report.

The settings use native SwiftUI controls:

- `Picker`
- `Toggle`
- `Button`
- `Link`

`AppPrefs` holds the settings:

```swift
struct AppPrefs {
	var areaMode = AreaMode.near
	var measurementUnit = MeasurementUnit.feet
	var directionStyle = DirectionStyle.words
	var intersectionWording = IntersectionWording.direct
	var spokenIntersectionCount = SpokenIntersectionCount.one
	var announcementOptions = AnnouncementOptions()
	var mapDetails = MapDetailOptions()
	var haptics = true
	var manhattanSnobMode = false
}
```

`AreaMode`, `MeasurementUnit`, `DirectionStyle`, `IntersectionWording`, and `SpokenIntersectionCount` are enums. Each enum provides a value or label for the native Settings controls. `AnnouncementOptions` stores the Distance, Direction, and Neighborhood toggles. Manhattan Snob Mode is a Boolean because it is just on or off.

Intersection wording uses a segmented control. Direct wording names both roads as an intersection. Street Context first names the road nearest the device, then identifies the other road. For example: `Upcoming: On E 20th Avenue, Main Street is about 140 feet ahead.` A short description below the control changes with the selection. If the nearest road cannot be matched confidently to the selected intersection, the report uses Direct wording instead.

Map detail controls whether extra OpenStreetMap details are included in the lookup. Crossings can add mapped crossing points on a named road. Walking Paths can include named paths such as footways when they intersect with streets or other named paths.

Walking Paths remains off by default. When enabled, first Upcoming as well as ranked Upcoming can follow a named mapped path and report its junction with a named street or another named path. Unnamed paths remain excluded because the app cannot provide an accurate intersection name for them. The Settings explanation makes clear that leaving the option off keeps results focused on the street grid.

Announcement content uses three toggles: Distance, Direction, and Neighborhood. The intersection name is always included. Turning all three toggles off gives compact intersection-name-only output. When several results share the same street, compact output names that street in the first intersection and then lists the remaining cross streets, such as `Amsterdam Avenue and West 93rd Street, West 94th Street`. When the results do not share a street, each intersection remains complete, such as `Foothill Boulevard and Frazier Avenue, Stanley Avenue and Talbot Avenue`.

The Announcements section progressively reveals dependent controls. When Distance is on, Measurement Unit appears so the user can choose feet or meters. When Direction is on, Direction Style appears as a segmented control with Relative, Cardinal, and Clock Face choices. Relative describes the intersection from the phone heading, such as `ahead and right`. Cardinal uses the geographic bearing from the user to the intersection, such as `northwest`. Clock Face uses wording such as `at 2 o'clock` and treats the direction the phone is pointing as 12 o'clock. The saved raw value `words` continues to select Relative so existing preferences remain compatible. Manhattan Snob Mode changes Cardinal and My Direction wording into New York-style wording. North and northeast become `Uptown`, east and southeast become `East Side`, south and southwest become `Downtown`, and west and northwest become `West Side`. A Cardinal intersection report can therefore say `about 120 feet toward Uptown`, while Relative and Clock Face reports remain unchanged. Neighborhood is disabled on a fresh installation. When it is enabled, Neighborhood Context appears as a segmented control with Nearby only and Nearby and toward choices. A sample string below the toggles updates as these settings change.

Spoken Intersections is a menu picker with values 1, 2, and 3. The selected number controls how many results the app requests. Nearest orders multiple results by straight-line distance. Upcoming uses the phone heading to choose a travel direction and orders intersections along the connected path of the current road. VoiceOver receives the complete labels `One intersection`, `Two intersections`, and `Three intersections`. The explanatory text for values 2 and 3 states exactly how many results Nearest and Upcoming will speak.

The `Show 2nd and 3rd Controls` toggle controls whether the main screen shows chevron menus for ranked Nearest and Upcoming results. Turning it off removes those visible menus, but Siri, Shortcuts, and VoiceOver custom actions still provide ranked access.

Settings groups use native `Section` headers. The Announcements section comes first and acts as the main builder for spoken output. More specialized sections, such as Intersection Wording, Spoken Intersections, Map Detail, and About Intersector, follow it.

This keeps display strings near the setting values they describe.

The Settings view also uses `@AccessibilityFocusState` for its setting controls. When a user changes a setting, the binding saves the new value and marks that same control as the accessibility focus target. That helps VoiceOver stay on the control that changed instead of jumping to the sheet's Done button after SwiftUI redraws the form.

The feedback button, privacy policy, acknowledgements, and app information are grouped in a native Form section headed `About Intersector`.

The Acknowledgements disclosure begins by thanking Jen Walz for inspiring the creation of Intersector, followed by the OpenStreetMap attribution and license link.

## Onboarding

`OnboardingView.swift` shows a small sequence of pages.

The onboarding pages are shown with a `NavigationStack`.

```swift
@State private var path: [Int] = []
```

The page content is stored in an array of `OnboardingPage` values.

When the user presses Next, the app pushes the next onboarding page onto the navigation path. That makes each onboarding step a real incoming screen instead of rewriting the title and body inside the same view. This structure gives VoiceOver a better native screen transition to work with when moving from one page heading to the next.

When the user reaches the final page, onboarding calls:

```swift
locationProvider.requestWhenInUseAuthorization()
```

Then it calls `onComplete()`, which lets `ContentView` set `hasCompletedOnboarding` to true.

This is a useful parent-child view pattern:

- The child view owns the onboarding screen.
- The parent view owns whether onboarding is complete.
- The child reports completion through a closure.

The onboarding flow also includes an Apple Watch support page. It tells users that the watch app is included and that they can install it from the Watch app on iPhone if it does not appear automatically.

## Apple Watch Companion App

The `IntersectorWatch` folder contains the first Apple Watch companion app pass.

The watch app has:

- a simple SwiftUI screen
- a Nearest button
- an Upcoming button
- visible result text
- watch App Intents for Siri and Shortcuts

The watch App Intents return dialog text so Siri on Apple Watch has a spoken result to use.

Scan Mode is not part of the first watch pass. It is a continuous heading-driven mode, while the first watch target is focused on short one-shot reports that make sense through Siri.

The watch target is embedded in the main Intersector iOS app target. That lets the watch app build along with the iOS app for TestFlight and App Store distribution.

## Siri And Shortcuts

`CrossStreetIntents.swift` defines App Intents.

Each intent is a struct that conforms to `AppIntent`.

For example:

```swift
struct NearestIntersectionIntent: AppIntent
```

The intent's `perform()` method loads the user's saved app preferences and calls the same shared service as the app UI:

```swift
let prefs = await AppPrefs.saved()
let text = try await OrientSvc.shared.spokenText(.nearest, prefs: prefs)
```

That is the important architecture choice. Siri does not have a separate intersection engine. It reuses the same app logic.

Dedicated 2nd Nearest, 3rd Nearest, 2nd Upcoming, and 3rd Upcoming intents request one exact rank directly. The service sorts nearest candidates by straight-line distance. Upcoming ranks follow only the connected geometry of the detected current road and do not substitute nearby off-road intersections. These ranked shortcut actions speak only the requested intersection, not the intersections leading up to it, and their spoken prefixes include the requested rank.

`IntersectorShortcuts` defines default shortcut phrases. Those phrases include `.applicationName`, which lets the system insert the app name.

## Error Text

Errors are represented with Swift error types.

`OrientError` handles app-level errors:

- no intersections
- heading unavailable
- location unavailable

`MapDataError` handles map server and parsing errors:

- invalid response
- server error
- invalid map data

Both conform to `LocalizedError`, which lets each error provide user-facing text through `errorDescription`.

In `ContentView`, the catch block uses:

```swift
error.localizedDescription
```

That means the specific error type controls the explanation, and the UI code does not need a large switch statement for every possible failure.

## Tests

The tests live in `crossStreetTests/crossStreetTests.swift`.

They currently cover:

- report text behavior
- upcoming intersection matching
- Scan Mode current-street filtering
- map cache reuse
- map cache behavior for distant results
- map cache behavior across several recent areas
- filtering non-street paths from intersection building

These tests focus on pure logic and data behavior. That is usually faster and more stable than testing everything through the UI.

The useful testing pattern is:

- Test algorithms directly when possible.
- Test model formatting directly.
- Test cache behavior without launching the app.
- Use UI tests only when the UI behavior itself is what you need to verify.

## Build Commands

The current scheme is `Intersector`.

For a normal compile check:

```sh
xcodebuild -project crossStreet.xcodeproj -scheme Intersector -destination 'generic/platform=iOS Simulator' build
```

For the simulator test suite on the available iPhone 16 simulator:

```sh
xcodebuild -project crossStreet.xcodeproj -scheme Intersector -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0' test
```

For logic-only changes, a build plus focused unit tests is usually enough. Full simulator UI tests are more useful when changing launch behavior, visible UI flow, or interactions that need the app to run.

## Engineering Practices Worth Learning From This App

This app uses several patterns that are common in production Swift apps:

- Small models for app data.
- Enums for known option sets.
- Protocols for replaceable services.
- Async functions for work that takes time.
- Continuations to bridge delegate APIs into async code.
- Actors for shared mutable state such as caches.
- Observable objects for longer-running feature controllers.
- SwiftUI state for screen updates.
- Native controls for standard interface behavior.
- Isolated algorithm files that are easy to test.
- Shared service logic reused by both UI and App Intents.

The larger lesson is separation of responsibility. Each file has a job. The UI asks for results, services gather data, model types hold data, finder types choose matches, and report types format output.

That separation makes the code easier to change because most edits stay close to one responsibility.
