# State for macOS

State is an open-source macOS file drive client with a native menu-bar app and Finder filesystem extension. The client currently connects directly to S3-compatible storage; it is not yet integrated with the State Drive API or shared-workspace identity.

## Project status

The current app is an early direct-to-provider implementation. It supports provider configuration, Finder-style browsing, uploads, previews, local labels, offline pins, and several mount modes. Workspace members and invitations are local UI state. See [`docs/architecture.md`](docs/architecture.md) for the staged plan to connect the client to a canonical shared-drive service.

## Build

Requirements: macOS 15.4 or later and Xcode 26 or later.

```sh
xcodebuild \
  -project apps/macos/PhotojellyFS.xcodeproj \
  -scheme PhotojellyFS \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

For a signed local build, select the `PhotojellyFS` scheme in Xcode and configure your own development team. FSKit mounting requires Apple's restricted `com.apple.developer.fskit.mount` and `com.apple.developer.fskit.fsmodule` entitlements. Without those entitlements, use the sparse-image fallback. This repository does not include signing certificates or a provisioning profile.

## Storage and privacy

In direct-provider mode, file bytes move between the Mac and the selected object store; they are not proxied through the State API. Provider configuration is currently saved in a local JSON file with owner-only permissions, not in the Keychain. Use a dedicated bucket and a key restricted to that bucket.

Optional semantic labels use a user-provided OpenRouter key. The key and file metadata are sent to OpenRouter only when that feature is invoked. The app also requests provider favicons from Google's favicon service.

## License

The source in this repository is released under the MIT License. Product names and marks are not licensed by the code license.
