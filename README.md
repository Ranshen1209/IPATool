# IPATool

<p align="center">
  <img src="IPATool/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="IPATool App Icon" width="160" height="160">
</p>

A native macOS tool built with SwiftUI that integrates Apple account sign-in, app version lookup, license requests, chunked downloading, verification, and IPA metadata rewriting into a single desktop workbench.


## Feature Overview

- Apple ID sign-in and session restoration
  The sign-in flow is initiated through a private Apple service protocol adapter layer. After a successful request, account credentials, verification codes, and session information are saved to Keychain, and cookies and login state are restored whenever possible.
- App version lookup
  After entering a numeric App ID, you can fetch the version list; you can also directly specify a Version ID to query a specific build.
- License requests
  Sends purchase/license status requests for the selected version and distinguishes statuses such as `licensed`, `already owned`, and `failed`.
- Download task workbench
  Creates download tasks after licensing succeeds, with support for pausing, canceling, retrying, deleting, revealing output and cache directories in Finder.
- Chunked downloading and resume support
  The downloader first resolves the remote size, then splits the file into chunks based on configuration. It supports concurrent downloads, persistent task lists, and restoration after app restart.
- IPA verification and rewriting
  After downloading completes, it can perform MD5 verification and write `iTunesMetadata.plist` and `SC_Info/*.sinf` signature data into the IPA.
- Logs and risk center
  Includes a built-in structured log viewer and a separate risk page that clearly indicates which flows are stable and which still depend on private Apple protocols.
- Sandbox-friendly directory authorization
  Output and cache directories are persisted through security-scoped bookmarks to better support the sandboxed environment of signed macOS apps.

## Current UI Structure

The app is divided into the following workspaces through a sidebar:

- `Account`
  Sign in, sign out, view the current Apple account session, and handle two-factor verification prompts.
- `Search`
  Enter App ID / Version ID, load available versions, request a license for the selected version, and create download tasks.
- `Tasks`
  View task progress, status, retry count, output path, and cache path.
- `Logs`
  View logs for sign-in, lookup, purchase, download, IPA rewriting, and other flows, with filtering by level.
- `Risks`
  Directly displays the built-in operational risk notes for the project.
- `Settings`
  Configure output directory, cache directory, chunk concurrency, chunk size, and clear the cache.

## Flows Actually Implemented in the Code

A typical workflow is as follows:

1. Enter your Apple ID and password on the `Account` page.
2. After a successful sign-in, the app writes account credentials and session state to Keychain.
3. Enter a numeric App ID on the `Search` page, and optionally enter a Version ID.
4. The app fetches version data through the catalog repository; if the private catalog does not return available versions, normal search attempts to fall back to public iTunes Lookup metadata.
5. Select a version and initiate a license request.
6. After the license succeeds, if the current version object lacks a downloadable URL or signature data, the app requests a “downloadable version” again.
7. After creating a download task, the chunk downloader writes the task to `tasks.json` and fetches chunks concurrently.
8. After all chunks are merged, the app moves the IPA to the target output directory, performs optional MD5 verification, then rewrites metadata and `sinf`.
9. The final result appears on the `Tasks` page, and the detailed process can be viewed on the `Logs` page.

## Project Structure


```text
IPATool/
├── App/              # AppContainer, AppModel, routing, Command menu
├── Data/             # DTOs, protocol adapter gateways, Repository
├── Domain/           # Domain models, protocols, UseCase
├── Infrastructure/   # HTTP, Keychain, downloader, logging, storage, IPA rewriting
├── Presentation/     # SwiftUI pages
└── Assets.xcassets/  # App resources and icons
```


- `App/AppContainer.swift`
  Responsible for dependency injection, wiring together settings, keychain, HTTP client, repositories, use cases, and downloader.
- `App/AppModel.swift`
  Responsible for orchestration of the entire app state and serves as the main coordination layer between the UI and use cases.
- `Data/Gateways/AppleServicesProtocolAdapters.swift`
  Encapsulates the three Apple protocol requests for sign-in, catalog, and purchase.
- `Data/Repositories/*`
  Converts the DTO / protocol layer into business-oriented `AuthServicing`, `AppCatalogServicing`, `PurchaseServicing`, `DownloadServicing`, and `IPAProcessingServicing`.
- `Infrastructure/Download/ChunkedDownloadManager.swift`
  One of the core implementations in the project, responsible for chunk planning, HTTP Range downloading, persistence, restoration, merging, retries, and status updates.
- `Infrastructure/Archive/IPAArchiveRewriter.swift`
  Unpacks, writes metadata / sinf, and repackages the IPA using system commands.
- `Presentation/*`
  The current SwiftUI desktop interface.

## Key Implementations

### 1. Sign-in and Keychain

- `AppleAuthRepository` saves the following after successful sign-in:
  - Apple ID / password
  - Reusable verification code
  - `AppSession`
  - Current Apple-related cookies
- At startup, `AppModel.bootstrap()` attempts to:
  - Restore sandbox directory access
  - Read persisted download tasks
  - Restore the cached Apple ID
  - Restore session and cookies from Keychain

### 2. Two-Factor Verification Handling

- On the first sign-in, it first attempts normal authentication.
- If Apple explicitly requires verification, `AppModel` presents `VerificationCodeSheet`.
- If a `Purchase Session Expired` error occurs during a license request, the app also attempts to restore the session using the cached verification code first; if that fails, it prompts for a new verification code.

### 3. Search and Version Resolution

- `AppleCatalogRepository` parses the song list returned by the private catalog.
- `StoreDTOMapper` derives candidate `externalVersionID` values from metadata.
- Normal search can fall back to the public `itunes.apple.com/lookup` when needed, but this fallback only provides basic metadata and does not guarantee downloadable URLs or signature information.

### 4. Chunked Downloading

The downloader does the following:

- Uses `HEAD` or `Range: bytes=0-0` to infer the remote file size.
- Generates a chunk plan according to the chunk size in settings.
- Downloads multiple chunks concurrently.
- Strictly validates:
  - HTTP status must be `206`
  - `Content-Range` must match
  - Chunk length must meet expectations
- Persists tasks and version context to `tasks.json`, supporting cold-start restoration.

### 5. IPA Processing

`IPAProcessingRepository` will:

- Perform verification when MD5 is available.
- Assemble the metadata dictionary and write it to `iTunesMetadata.plist`.
- Decode base64 `sinf` data and write it to the corresponding location under `SC_Info`.
- Use `IPAArchiveRewriter` to call `/usr/bin/ditto` and `/usr/bin/zip` to repackage the IPA.

## Configuration and Local Data

The app currently stores local state across several locations:

- Keychain
  Stores account credentials and restored sessions.
- `~/Library/Application Support/IPATool/settings.json`
  Stores output directory, cache directory, chunk concurrency, and chunk size.
- `~/Library/Application Support/IPATool/bookmarks.plist`
  Stores security-scoped bookmarks for directory access.
- Default cache directory
  `~/Library/Caches/IPATool`
- Default output directory
  `~/Downloads`

## Environment Requirements

- macOS
- Xcode 26.4 or a compatible version
- SwiftUI / Observation
- Network access allowed

The project already enables this entitlement:

- `com.apple.security.network.client`

## How to Run

### Using Xcode

1. Open [IPATool.xcodeproj](/Volumes/APFS_HD/Documents/Xcode/IPATool/IPATool.xcodeproj) with Xcode
2. Select the `IPATool` scheme
3. Run the macOS app directly

### First Use

1. Open `Settings`
2. Confirm the output directory and cache directory
4. Sign in under `Account`
5. Search for an app in `Search`

## Test Coverage

The repository currently includes a set of unit tests, mainly covering the following behaviors:

- Logging in the sign-in use case
- Mapping plist responses in the Apple sign-in gateway
- `AppModel` pauses download tasks that require authentication before signing out
- Mutual exclusion protection for concurrent verification code requests
- Preserving `tasks.json` when clearing the cache
- Restoration semantics of download task state
- Restoration of persisted version context when recovering download tasks on cold start
- Failure protection when an HTTP Range response is invalid

The test directory is at [IPAToolTests](/Volumes/APFS_HD/Documents/Xcode/IPATool/IPAToolTests).

## Risks and Boundaries

This part is very important, because the code itself explicitly marks these as risk items:

- Apple sign-in, catalog lookup, and purchase/license requests depend on private or undocumented Apple service protocols.
- These protocols may stop working at any time and may also cause account risk control, legal, or compliance issues.
- IPA metadata / `sinf` rewriting is clearly a policy-sensitive capability and is not suitable as a public-facing App Store feature.
- The project is currently more suitable for:
  - Internal research
  - Developer experimentation
  - Private distribution environments
- It is not suitable to directly claim as:
  - A stable production tool
  - A public Mac App Store product

## Credit

[IPATool.js](https://github.com/wf021325/ipatool.js)
[Codex](https://github.com/openai/codex)
