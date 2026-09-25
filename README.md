# CiteKit

A native macOS citation assistant. Highlight a URL or identifier in a document, press **Option–Command–C**, and copy an MLA 9, APA 7 or BibTeX citation.

CiteKit includes a Spotlight-style panel, quote capture, searchable local history, metadata conflict resolution, confidence reports, and configurable shortcuts and providers. It runs in the menu bar and can launch at login.

## Build and run

Requires macOS 14+, Swift 6 command-line tools or Xcode, and Git. The bundled Node runtime currently targets **Apple silicon**.

For a fresh checkout, prepare the pinned Zotero dependencies once:

```sh
./scripts/fetch-node-runtime.sh
export PATH="$PWD/.build/node-v24.21.0-darwin-arm64/bin:$PATH"
git clone https://github.com/zotero/translation-server.git .build/zotero-server
git -C .build/zotero-server checkout 3a9d17614896fc1fea73d7b880ea79273b605275
git -C .build/zotero-server submodule update --init --recursive
(cd .build/zotero-server && npm ci --omit=dev)
```

Then build and launch:

```sh
./scripts/test.sh
./scripts/build-app.sh
open build/CiteKit.app
```

Open `Package.swift` in Xcode to develop. Build scripts share SDK and module-cache configuration in `scripts/toolchain.sh`. Downloaded dependencies and app bundles are generated locally and excluded from Git.

## Use CiteKit

1. Open the app and find its quotation-mark menu-bar icon.
2. Enable CiteKit in **System Settings → Privacy & Security → Accessibility** to capture selected text.
3. Highlight an actual URL or identifier in your document and press **Option–Command–C**. Alternatively, use **Paste Source…** or **Cite Clipboard** from the menu; these do not require Accessibility permission.
4. Choose MLA, APA or BibTeX, inspect source health, and copy the citation.

Try `10.1038/nphys1170`, `PMID: 31452104`, `arXiv:1706.03762`, `ISBN:9780306406157`, or an article URL. Providers include Crossref, PubMed, arXiv, Open Library, webpage metadata and optional Zotero extraction.

Turn on **Preferences → Use Zotero** to start the bundled service automatically. End users need no Node installation, terminal command or server address. Advanced settings support a separately managed custom server.

Generated sources save automatically. Highlight prose to capture a quote, then supply its source and page number. History lets you search, reopen, recopy and delete sources and their saved quotes. Data stays in `~/Library/Application Support/CiteKit/History.sqlite`.

Preferences control citation style, copy behavior, the global shortcut, providers, menu-bar visibility and login launch. Escape or clicking elsewhere dismisses the panel; CiteKit keeps running until you quit it. Hiding its menu-bar icon makes it available in the Dock.

See the [feature and confidence guide](Docs/ProvidersAndConfidence.md) and the [manual testing walkthrough](Docs/ManualTesting.md) for details.

## Project map

| Location | Purpose |
| --- | --- |
| `Package.swift` | Swift package targets and bundled resources |
| `Sources/CiteKitApp/` | macOS interface, preferences, history storage, selection capture and Zotero lifecycle |
| `Sources/CiteKitCore/` | Source identification, provider requests, verification and citation formatting |
| `Sources/CiteKitCore/Resources/` | Bundled citation styles, formatter and licenses |
| `Support/Zotero/managed-server.cjs` | Adapter that runs the bundled Zotero server privately |
| `Tests/` | Automated tests and sample HTML pages for manual testing |
| `scripts/` | Build, test and dependency helpers |
| `Docs/` | Feature guide, testing walkthrough, third-party notices and resource checksums |

For the app, start with `CiteKitApp.swift` and `Views.swift`. For citation processing, start with `SourceClassifier.swift`, then `Resolver.swift`; providers, verification and formatting are in their named files.

## Testing

```sh
# Default automated tests
./scripts/test.sh

# Include tests against live metadata APIs (requires internet)
CITEKIT_LIVE_TESTS=1 ./scripts/test.sh

# Test the actual bundled Zotero service after building the app
CITEKIT_MANAGED_ZOTERO_TESTS=1 CITEKIT_PACKAGED_ZOTERO_APP="$PWD/build/CiteKit.app" ./scripts/test.sh --filter LocalZoteroServerTests
```

For custom-server development only, `scripts/start-zotero.sh` starts the prepared server using Node from your PATH. The standalone pipeline test uses `CITEKIT_ZOTERO_LIVE_TESTS=1`. Normal app use does not need this helper.

Follow [ManualTesting.md](Docs/ManualTesting.md) for UI, cross-editor selection, confidence fixtures and login-launch checks. Automated tests do not establish compatibility with every editor.

## Privacy and current limits

Selection is read only when invoked, without replacing your clipboard. Clipboard access is explicit. Source URLs and identifiers go to the selected providers; quotes and history stay local. No telemetry or cloud sync.

Confidence describes metadata evidence and completeness, not scientific validity. Webpage extraction may be limited by dynamic sites and paywalls. Copy output is plain text. PDF import, automatic browser/PDF source association, title search, free-form metadata editing and project bibliographies are not implemented.

The app is ad-hoc signed for development. Rebuilding may require Accessibility reauthorization. Use a stable app location for login launch. Intel packaging and production signing/notarization are not implemented.

The Zotero dependency installation previously reported 14 audit findings (9 moderate, 2 high, 3 critical); these have not been remediated or freshly audited. Review dependencies before production distribution. Third-party attribution and licensing details are in [ThirdPartyNotices.md](Docs/ThirdPartyNotices.md); vendored resource hashes are in [ResourceChecksums.txt](Docs/ResourceChecksums.txt).
