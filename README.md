# CiteKit

**v0.1.0 — Early preview. Working features are available, but bugs and rough edges are expected.**

Create citations from article links, DOIs, PubMed IDs, arXiv IDs, and book ISBNs without leaving your document.

## What you can do

- Generate MLA 9, APA 7, and BibTeX citations.
- Capture highlighted text with a keyboard shortcut.
- Save quotes with their sources and page numbers.
- Search your citation history and copy saved citations again.
- Review missing information, conflicting metadata, and citation confidence.

## Getting started

Requires **macOS 14 or later on an Apple silicon Mac**. New source lookups require an internet connection.

Check [Releases](https://github.com/Vedanth-R/Citation-Tracker/releases) for available downloads. To build the app yourself, follow the [build instructions](Docs/ProvidersAndConfidence.md#build-and-run).

1. Open CiteKit and click its quotation-mark icon in the menu bar.
2. Choose **Paste Source…**, paste a link or identifier, and press Return.
3. Select **MLA 9**, **APA 7**, or **BibTeX**, then copy your citation.

To capture text directly from a document, enable CiteKit in **System Settings → Privacy & Security → Accessibility**. Highlight a URL or identifier and press **Option–Command–C**. If your editor does not support selection capture, copy the text and choose **Cite Clipboard** instead.

Highlighting a passage captures it as a quote; add its source and page number to save it with a citation. Sources are saved automatically in **History**.

## Settings

Open **Preferences** to change the keyboard shortcut, default citation style, copy behavior, and launch-at-login setting.

Enable **Use Zotero** for additional webpage metadata extraction. CiteKit manages the bundled service automatically; no separate Zotero installation or server setup is needed.

Closing the panel keeps CiteKit running in the background. Use **Quit CiteKit** from its menu to exit.

## Privacy and limitations

History and quotes stay on your Mac. Source links and identifiers are sent to the enabled metadata providers. CiteKit does not continuously monitor your clipboard or collect telemetry.

Review citations before using them. Confidence reflects the available citation metadata, not the quality of the research. Some websites and editors may not work fully, copied citations are plain text, and PDF import is not supported. This preview is not notarized by Apple.

[Feature details](Docs/ProvidersAndConfidence.md) · [Testing walkthrough](Docs/ManualTesting.md) · [Third-party notices](Docs/ThirdPartyNotices.md)
