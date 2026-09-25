# Providers, verification and confidence

## Highlighting a URL

1. Open `build/CiteKit.app` and enable CiteKit in System Settings → Privacy & Security → Accessibility.
2. Return to your document and highlight the actual URL text.
3. Press **Option–Command–C**, or your configured shortcut.
4. CiteKit reads the selected text before activating its panel, resolves the source, and shows its citation and confidence report.

The selection reader uses AXSelectedText, then AXSelectedTextRange and the range-string API, then the selected UTF-16 range within the focused text element's value. It never simulates Command-C or replaces your clipboard to retrieve a selection. If an editor does not expose a readable selection, copy it yourself and use **Cite Clipboard**. Granting permission is a macOS user action; CiteKit cannot grant it for you.

## Providers

| Input | Lookup | Meaning of success |
| --- | --- | --- |
| DOI / doi.org URL | Crossref | Returned DOI matches the requested identifier |
| `PMID: 31452104` / PubMed URL | NCBI PubMed EFetch | Returned PMID matches; journal, date, authors and DOI normalized |
| `arXiv:1706.03762` / arXiv URL | arXiv Atom API | Preprint identifier/version matches; journal-version DOI is not substituted |
| ISBN-10 or ISBN-13 | Open Library ISBN edition + author records | Checksum validated; ISBN-10/13 equivalents matched to the edition |
| Web URL | JSON-LD / academic / common HTML metadata | Extracted, not independently verified |
| Web URL with configured server | Zotero Translation Server `/web` | One translated item; ambiguous multi-item results are rejected |

PubMed, arXiv, ISBN and webpage comparison can be configured in Preferences. Crossref is the core DOI provider. Unknown titles/prose do not trigger silent web searches. arXiv calls are spaced at least three seconds apart. Quotes are never sent to providers.

Enable **Use Zotero** in Preferences. CiteKit bundles the Translation Server and Node runtime, starts an authenticated localhost service automatically, waits for readiness, and stops its own service when disabled or on quit. No terminal or server address is needed. The saved preference also restores the service on app launch. If the child exits, the next lookup retries startup. Failed startup is included in the confidence report.

An optional custom endpoint is available under **Advanced Zotero connection**. That mode connects to a separately managed server and never starts/stops that server. Remote endpoints require HTTPS. Only source URLs are sent, never quote text.

## Confidence

- **Verified:** DOI matched Crossref, essential fields present, no metadata conflicts or failed attempted checks.
- **High:** Complete structured metadata from another identifier provider or Zotero, or a DOI source with an unavailable secondary check.
- **Medium:** Conflicts or limited completeness with structured backing, or usable unverified webpage metadata.
- **Low:** Several essential fields missing, missing title, or weak extraction without sufficient structured backing.

Missing DOI alone does not establish unreliability: a book or PubMed article can still have high confidence. Missing DOI verification *and* Zotero extraction is explicitly reported. Zotero is an extraction layer, not independent proof. Confidence evaluates citation metadata, not scientific quality or peer review.

## Conflict handling

The merger compares title, author list, date, publication, publisher, volume, issue, pages and DOI. It retains alternatives and field provenance, with field-specific provider priorities. Compatible date precision and expanded author initials are accepted without a conflict; differing middle names, years or titles remain visible. Crossref generally wins journal fields; PubMed gets priority for dates and authors. Fuller compatible authors/dates can fill gaps.

Expand **Metadata conflicts** to inspect both values and choose one. Citations regenerate and the choice persists with history. The discrepancy remains recorded and confidence remains limited; choosing a value does not independently verify it. Conflicting DOIs require a fresh lookup rather than silently changing the identity of a saved source.

## Preferences

- Global shortcut recorder with immediate registration and rollback on conflicts.
- Default MLA, APA or BibTeX style applies immediately.
- Primary Copy action: full citation, in-text citation, or a choice each time.
- Launch at login through macOS Service Management; macOS may require approval in Login Items.
- Hide/show menu-bar icon; hiding it makes the app available in the Dock.
- Provider toggles, webpage comparison, automatic local Zotero and optional custom endpoint settings.

Login launch should be used from a stable app location. Development rebuilds use ad-hoc signing, so macOS may require Accessibility permission again.

## Primary API documentation

- Crossref: https://www.crossref.org/documentation/retrieve-metadata/rest-api/
- PubMed: https://www.nlm.nih.gov/dataguide/edirect/efetch.html
- arXiv: https://info.arxiv.org/help/api/user-manual.html
- Open Library editions/ISBN: https://openlibrary.org/dev/docs/api/books
- Zotero Translation Server: https://github.com/zotero/translation-server
- Login launch: https://developer.apple.com/documentation/servicemanagement/smappservice

## Development

See the [manual testing guide](ManualTesting.md) for feature walkthroughs.

`Support/Zotero/managed-server.cjs` wraps the unmodified upstream server. It binds to an OS-assigned loopback port, authenticates requests with a per-launch token, writes readiness to a private temporary directory, and exits if CiteKit's stdin pipe closes or its parent process disappears. No dependencies are downloaded when the app launches.

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

## Automated testing


```sh
# Default automated tests
./scripts/test.sh

# Include tests against live metadata APIs (requires internet)
CITEKIT_LIVE_TESTS=1 ./scripts/test.sh

# Test the actual bundled Zotero service after building the app
CITEKIT_MANAGED_ZOTERO_TESTS=1 CITEKIT_PACKAGED_ZOTERO_APP="$PWD/build/CiteKit.app" ./scripts/test.sh --filter LocalZoteroServerTests
```

For custom-server development only, `scripts/start-zotero.sh` starts the prepared server using Node from your PATH. The standalone pipeline test uses `CITEKIT_ZOTERO_LIVE_TESTS=1`. Normal app use does not need this helper.

Follow [ManualTesting.md](ManualTesting.md) for UI, cross-editor selection, confidence fixtures and login-launch checks. Automated tests do not establish compatibility with every editor.


The Zotero dependency installation previously reported 14 audit findings (9 moderate, 2 high, 3 critical); these have not been remediated or freshly audited. Review dependencies before production distribution. See [third-party notices](ThirdPartyNotices.md) for licensing details.
