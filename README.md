# CiteKit

**v0.1.0 — Early preview. Working features are available, but bugs and rough edges are expected.**

Create citations from article links, DOIs, PubMed IDs, arXiv IDs, and book ISBNs without leaving your document.

## What you can do

- Generate MLA 9, APA 7, and BibTeX citations.
- Capture highlighted text with a keyboard shortcut.
- Find scholarly sources from a title, author, year, or publication name.
- Save quotes with their sources and page numbers.
- Search your citation history and copy saved citations again.
- Open the dashboard for library totals, activity stats, and a shortcut guide.
- Review missing information, conflicting metadata, and citation confidence.

## Getting started

Requires **macOS 14 or later on an Apple silicon Mac**. New source lookups require an internet connection.

Check [Releases](https://github.com/Vedanth-R/Citation-Tracker/releases) for available downloads. To build the app yourself, follow the [build instructions](Docs/ProvidersAndConfidence.md#build-and-run).

1. Open CiteKit. A loading screen appears while it prepares your workspace; you can continue in the background. Click its quotation-mark icon in the menu bar.
2. Choose **Paste Source…**, paste a link or identifier, and press Return.
3. Select **MLA 9**, **APA 7**, or **BibTeX**, then copy your citation.

To capture text directly from a document, enable CiteKit in **System Settings → Privacy & Security → Accessibility**. Highlight a URL or identifier and press **Option–Command–C**. If your editor does not support selection capture, copy the text and choose **Cite Clipboard** instead.

**No URL?** Highlight a title or partial reference and press **Option–Command–F**, or choose **Find Sources…** from the menu. Review the suggested scholarly sources and click **Cite this source**. For websites outside Crossref’s coverage, use the browser-search button and paste the chosen URL.

Highlighting a passage with Option–Command–C captures it as a quote; add its source and page number to save it with a citation. Sources are saved automatically in **History**.

Open **Dashboard** from the menu bar for your research overview, history, and commands. Choose **Dashboard in Full Screen**, or click the capture panel’s expand button, for a larger workspace. Activity counters stay on your Mac and start when you use this version.

## Settings

Open **Preferences** to change the keyboard shortcut, default citation style, copy behavior, and launch-at-login setting.

Enable **Use Zotero** for additional webpage metadata extraction. CiteKit manages the bundled service automatically; no separate Zotero installation or server setup is needed.

Closing the panel keeps CiteKit running in the background. Use **Quit CiteKit** from its menu to exit.

## Privacy and limitations

History and quotes stay on your Mac. Source links and identifiers are sent to the enabled metadata providers. Explicit source searches send the selected or entered search text to Crossref. Startup also makes fixed public availability requests to enabled APIs, without sending your research data. CiteKit does not continuously monitor your clipboard or collect telemetry.

Review citations before using them. Confidence reflects the available citation metadata, not the quality of the research. Some websites and editors may not work fully, copied citations are plain text, and PDF import is not supported.

[Third-party notices](Docs/ThirdPartyNotices.md)
