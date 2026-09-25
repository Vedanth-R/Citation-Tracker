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

See the [README](../README.md#build-and-run) for source setup, build commands and automated tests, and the [manual testing guide](ManualTesting.md) for feature walkthroughs.

`Support/Zotero/managed-server.cjs` wraps the unmodified upstream server. It binds to an OS-assigned loopback port, authenticates requests with a per-launch token, writes readiness to a private temporary directory, and exits if CiteKit's stdin pipe closes or its parent process disappears. No dependencies are downloaded when the app launches.
