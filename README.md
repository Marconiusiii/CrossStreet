# Intersector

Intersector is an accessibility-first iOS app for quickly identifying nearby intersections and orienting by street direction. It is designed for fast use from the app itself or through Siri Shortcuts, with VoiceOver announcements and haptic feedback for supported workflows.

## Features

- Find the nearest mapped intersection from your current location.
- Find an upcoming intersection based on your current heading.
- Use Scan Mode to point the phone toward nearby intersections on the street you are on.
- Start common actions through Siri Shortcuts without opening the app first.
- Hear updated information through VoiceOver announcements.
- Use optional haptic scan feedback while orienting the phone.
- Adjust neighborhood context, verbosity, and haptic preferences in Settings.

## Siri Shortcuts

Intersector provides App Shortcuts for:

- `Nearest intersection in Intersector`
- `Upcoming intersection in Intersector`
- `Start Scan Mode in Intersector`

You can also create your own shortcut phrases using Intersector actions in the Shortcuts app.

## Accessibility

Intersector is built around VoiceOver-first use. The main screen uses large full-width action areas, native SwiftUI controls where possible, Dynamic Type-friendly text, and spoken announcements when intersection information updates.

Scan Mode is a live orientation feature: when enabled, it monitors heading changes, announces matching intersections, and provides haptic feedback as the phone points closer to an intersection.

## Map Data

Intersector uses OpenStreetMap data through Overpass to find nearby streets and intersections.

Map data is from OpenStreetMap and is available under the Open Database License. More information is available at:

https://www.openstreetmap.org/copyright

## Requirements

- iOS 17.6 or later
- Xcode 16 or later
- Location permission for intersection lookup

## Building

Open `crossStreet.xcodeproj` in Xcode, select the `Intersector` scheme, and build for an iOS device or simulator.

For a quick command-line compile check:

```sh
xcodebuild -project crossStreet.xcodeproj -scheme Intersector -destination 'generic/platform=iOS Simulator' build
```

## Developer Documentation

For a plain-language guide to how the app code works, see `Documentation/README.md`.

## Privacy

Intersector uses location and heading information to provide intersection context. It does not create accounts, sell personal information, show ads, or intentionally collect analytics. See `privacy.html` for the project privacy policy.

## License

Intersector is released under the MIT License. See `LICENSE` for details.
