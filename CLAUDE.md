# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RClick is a macOS desktop application that extends Finder's context menu with custom functionality. It's a menu bar application that adds various right-click actions to macOS Finder, built with Swift and SwiftUI.

**Key Technologies:**
- Swift / SwiftUI (all UI components). Note: the project constitution (QWEN.md) mandates Swift 6.2 syntax, but the Xcode build settings currently pin `SWIFT_VERSION = 6.0` (main app) and `5.0` (some targets). Write Swift 6-compatible code; don't assume 6.2-only features compile.
- AppKit (system integration only — `NSWorkspace`, `NSOpenPanel`, file ops — no UI)
- SwiftData (persistence) + `UserDefaults` app group (config shared with the extension)
- FinderSync framework (Finder extension)
- DistributedNotificationCenter (inter-process communication)
- macOS 15.0+ deployment target; Xcode 16+ required
- SPM dependencies: `ZIPFoundation`, `swift-collections`

**App group identifier:** `group.cn.wflixu.RClick` (`Constants.suitName` — note the typo `suitName`, kept intentionally; it's referenced across the codebase). Both processes share data through this group.

## Architecture

RClick follows a dual-process architecture:

### 1. Main Application (`RClick/`)
- SwiftUI-based menu bar application
- Manages global settings and state via `AppState.swift`
- Provides settings interface (Settings window)
- Handles file operations triggered from context menu
- Entry point: [RClickApp.swift](RClick/RClickApp.swift)

### 2. FinderSync Extension (`FinderSyncExt/`)
- Runs as a separate process, injected into Finder
- Injects custom context menu items into Finder
- Communicates with main app via `Messager` class
- Entry point: [FinderSyncExt.swift](FinderSyncExt/FinderSyncExt.swift)

### 3. Communication Layer
The main app and extension communicate via `DistributedNotificationCenter`, wrapped by the `Messager` singleton ([Messager.swift](RClick/Shared/Messager.swift)). Every message is a JSON-encoded `MessagePayload { action, target, rid, trigger }`; the **`action` string is the real dispatch key**, not the notification name.

Actual notification channels (see `Key` in [StringExtension.swift](RClick/Shared/StringExtension.swift) and the `messager.on(...)` / `messager.sendMessage(...)` call sites):
- **Extension → App**: notification name `Key.messageFromFinder` (= `"RCLICK_FINDER_Main"`). Carries actions like `heartbeat`, `open`, `actioning`, `Create File`, `common-dirs`. Handled in [RClickApp.swift](RClick/RClickApp.swift) (`messager.on(name: Key.messageFromFinder)`, switch on `payload.action`).
- **App → Extension**: ad-hoc notification names `"running"` (app launched, sent on startup) and `"quit"` (app terminating). The extension subscribes to these in [FinderSyncExt.swift](FinderSyncExt/FinderSyncExt.swift) to track `isHostAppOpen`.

> Note: there is no `RClick.MessageFromApp` channel. The spec contract at [specs/001-macos-app-macos/contracts/app-extension-communication.md](specs/001-macos-app-macos/contracts/app-extension-communication.md) describes an idealized protocol that diverges from the shipped names above — trust the code.

### 4. State Management
- **AppState**: Centralized `ObservableObject` managing all app state
  - Apps: External applications that can open files
  - Dirs: Permissive directories (with security bookmarks)
  - Actions: Custom context menu actions
  - NewFiles: File templates for creation
  - CommonDirs: Quick access folders
- Persistence: SwiftData with shared container between app and extension
- Location: [AppState.swift](RClick/AppState.swift)

### 5. Data Models
All models are in [RClick/Model/](RClick/Model/):
- `Models.swift`: SwiftData `@Model` definitions (PermDir, OpenWithApp, RCAction, NewFile, CommonDir)
- `RCBase.swift`: Base protocol for common functionality
- `ModelContainer.swift`: Shared SwiftData container configuration

## Build and Development Commands

### Building
```bash
# Build the project
xcodebuild -project RClick.xcodeproj -scheme RClick -destination 'platform=macOS'

# Build for release
xcodebuild -project RClick.xcodeproj -scheme RClick -configuration Release
```

### Running
- Open `RClick.xcodeproj` in Xcode 16+
- Select the RClick scheme
- Press Cmd+R to build and run
- The FinderSync extension will be automatically registered

### Testing
There is **no test target** in `RClick.xcodeproj` yet (only `RClick` and `FinderSyncExt` schemes exist). The command below will only work once a test target is added:
```bash
xcodebuild test -project RClick.xcodeproj -scheme RClick -destination 'platform=macOS'
```

### Linting
No `.swiftlint.yml` is committed. `swiftlint` will run with defaults only if installed globally:
```bash
swiftlint
```

## Key Development Patterns

### Adding New Context Menu Actions

1. Define action model in [Models.swift](RClick/Model/Models.swift)
2. Add to `RCAction.all` static property
3. Handle action in [RClickApp.swift](RClick/RClickApp.swift) in `actionHandler()` method
4. Extension receives action via menu callback and sends message to main app

### Adding New File Templates

1. Add to `NewFile` model in [Models.swift](RClick/Model/Models.swift)
2. Add template file to [Assets.xcassets](RClick/Assets.xcassets/)
3. Handle creation in [RClickApp.swift](RClick/RClickApp.swift) in `createFile()` method

### Inter-Process Communication

When adding new message types:
1. Define `MessagePayload` structure in [Messager.swift](RClick/Shared/Messager.swift)
2. Register message handler in appropriate init method
3. Update contract documentation in [specs/001-macos-app-macos/contracts/app-extension-communication.md](specs/001-macos-app-macos/contracts/app-extension-communication.md)

### Security-Scoped Resource Access

When working with files outside app sandbox:
1. User must grant permission via `NSOpenPanel`
2. Store bookmark data using `URL.bookmarkData(options: ...)`
3. Access files with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
4. See `deleteFoldorFile()` and `createFile()` in [RClickApp.swift](RClick/RClickApp.swift) for examples

## Important Constraints

### RClick Constitution Requirements
- **MUST use Swift 6.2 syntax** - no older Swift patterns
- **MUST use SwiftUI for all UI** - no AppKit UI components
- **AppKit usage limited to system integration only** (e.g., NSWorkspace, NSPasteboard, file operations)
- **Target macOS 15 Sequoia and above only**

### Extension Development
- Extension runs in separate process with limited memory
- Must handle `isHostAppOpen` state - don't block if main app not available
- Use heartbeat mechanism to verify main app is running
- See [FinderSyncExt.swift](FinderSyncExt/FinderSyncExt.swift)

### Logging
- Use `@AppLog` property wrapper for structured logging
- Logs use `os.log` framework
- Category parameter should describe the subsystem
- Example: `@AppLog(category: "AppState") private var logger`

### Data Persistence
- SwiftData models use `@Model` macro
- Shared container via app group: `.group` `UserDefaults`
- Shared model container: `SharedDataManager.sharedModelContainer`
- Both app and extension access same database

## Directory Structure

```
RClick/
├── RClick/                        # Main application target
│   ├── RClickApp.swift           # App entry point & AppDelegate
│   ├── AppState.swift            # Global state management
│   ├── Model/                    # SwiftData models
│   ├── Settings/                 # Settings views (UI)
│   ├── Shared/                   # Utilities & services
│   ├── Assets.xcassets/          # Images, templates, icons
│   └── Resources/                # Localization files
├── FinderSyncExt/                # Finder extension target
│   ├── FinderSyncExt.swift       # Extension main file
│   └── MenuItemClickable.swift   # Menu item handlers
├── specs/                        # Feature specifications & contracts
└── RClick.xcodeproj             # Xcode project
```

## Common Issues

### Extension Not Loading
- Ensure extension is enabled in System Settings → Privacy & Security → Extensions
- Check that `FIFinderSyncController.default().directoryURLs` is set
- Verify heartbeat messages are being sent/received

### Security-Scope Access Fails
- Ensure bookmarks are stored and retrieved correctly
- Check `isStale` flag and refresh bookmarks if needed
- Always call `stopAccessingSecurityScopedResource()` when done

### SwiftUI Views Not Updating
- Ensure `@MainActor` annotation when updating `@Published` properties
- Use `@StateObject` instead of `@ObservedObject` for view-owned objects
- Remember `AppState.shared` is a singleton - use `@StateObject` appropriately

## Documentation References

- **Feature Specifications**: [specs/001-macos-app-macos/](specs/001-macos-app-macos/)
- **Development Guidelines**: [QWEN.md](QWEN.md)
- **Communication Protocol**: [specs/001-macos-app-macos/contracts/app-extension-communication.md](specs/001-macos-app-macos/contracts/app-extension-communication.md)
- **Data Model**: [specs/001-macos-app-macos/data-model.md](specs/001-macos-app-macos/data-model.md)
