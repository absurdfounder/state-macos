# State macOS client

This is the SwiftUI menu-bar app and Finder filesystem extension for State. The current Xcode project and several persistent identifiers retain the original PhotojellyFS names while the product UI is branded State.

The app is currently a direct-to-provider client. It connects to S3-compatible object storage using credentials configured on the Mac. It has not yet been integrated with the State Drive API, shared workspace identity, remote MCP, or server-managed memberships.

## Build

Requires macOS 15.4+ and Xcode 26+.

```sh
xcodebuild \
  -project PhotojellyFS.xcodeproj \
  -scheme PhotojellyFS \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

To build and run from Xcode, select the `PhotojellyFS` scheme and configure your own development team. FSKit mounting requires Apple's restricted mount and module entitlements. The app can use the sparse-image fallback when those entitlements are unavailable.

## Storage setup

Configure an S3-compatible provider in Settings. The project supports Backblaze B2, AWS S3, Cloudflare R2, Wasabi, and MinIO, plus optional SMB and local-folder locations. Use a dedicated bucket and a key restricted to that bucket.

The provider configuration is stored in `~/Library/Application Support/PhotojellyFS/drive.json` with owner-only permissions. It is not stored in this repository. The app does not yet use Keychain for provider credentials.
