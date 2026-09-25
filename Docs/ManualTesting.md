# CiteKit 0.4 manual testing checklist

Use `build/CiteKit.app`. These are expected behaviors to verify, not a claim that every GUI/application combination has already been tested. Use disposable test sources/quotes when checking deletion and deliberately incorrect metadata.

1. **Launch/background:** Open the app, locate its quotation-mark menu-bar icon, and choose Paste Source. Dismiss with Escape, close History/Preferences, and invoke the shortcut again. The app stays running until Quit CiteKit. Hiding the menu icon adds a Dock icon.
2. **Accessibility:** Enable CiteKit under System Settings → Privacy & Security → Accessibility. Return to TextEdit, select actual URL text, and press Option–Command–C. Repeat in your usual editor/browser. Rebuilding the development app may require reauthorization. When an app exposes no selection, the popup should offer manual clipboard/paste fallback without changing the clipboard itself.
3. **Highlight URL:** Use `https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0000308`. Select the URL text and invoke the shortcut. Expect a popup with the article citation. Link labels such as “click here” are not URL text.
4. **Paste/clipboard:** Paste a source into the panel and press Return or the return-arrow button. Menu → Cite Clipboard retrieves and generates immediately. The empty panel's Use clipboard fills the field; press Return to generate.
5. **Identifiers:** Test `10.1038/nphys1170`, `https://doi.org/10.1038/nphys1170`, `PMID: 31452104`, `https://pubmed.ncbi.nlm.nih.gov/31452104/`, `arXiv:1706.03762`, `https://arxiv.org/abs/1706.03762`, `ISBN:9780306406157`, and `0306406152`. Inspect Source health for matching provider/identifier status. Books should have book formatting. arXiv should retain preprint identity. A bare PMID number is not classified automatically.
6. **Validation/normalization:** Paste invalid ISBN `9780306406158`; expect an unrecognized-source error rather than an invented book. DOI URL tracking parameters/fragments should not change its identity. Repeat local complete fixture URL with `?utm_source=test#section`; it should deduplicate.
7. **Formats/copy:** Switch MLA 9, APA 7 and BibTeX. Paste copied output into TextEdit and compare it to the displayed citation. Primary Copy/Command-1 follows Preferences. More-copy menu offers explicit Full citation, BibTeX/Command-3 and APA narrative when in APA mode. Current clipboard output is plain text; italics are not preserved.
8. **In-text/pages:** For the PLOS article enter `42` and then `42–43`. MLA should include the locator, APA should use p./pp. Copy with the document icon/Command-2. In APA, use the more-copy menu to check narrative output. These locators are test inputs, not verified page numbers for that article.
9. **Quotes:** Highlight synthetic prose in TextEdit, invoke the shortcut, supply its source manually, and generate. Enter a page, Save quote, then Copy quote + citation/Command-4. Find the source in History and expand Saved quotes. Clicking a quote restores text/page. Automatic source detection and PDF page discovery are not implemented.
10. **History/search:** Generated sources are saved automatically. Search by title, author, publication or DOI. Reopen an entry and copy each format. Repeat the DOI and DOI URL; expect one record. ISBN-10/13 equivalents should share a source. Save two different quotes on one source; expect two quotes under one record.
11. **Persistence/deletion:** Quit and reopen the app; sources, quotes and preferences should remain. Recopy a saved entry while offline. Right-click a disposable source → Delete Source; its quotes should disappear too, including after restarting. No undo exists yet.
12. **Automatic Zotero:** Enable Use Zotero in Preferences, keeping custom-server mode off. Expect Starting then Ready. Generate the PLOS URL and find Zotero → Extracted in Source health. Disable/re-enable; it should stop/restart without Terminal. Quit/reopen with it enabled; readiness should return automatically. Known identifiers may use direct APIs without a Zotero extraction step, so use the publisher URL for this check.
13. **Confidence:** Verified, High, Medium and Low describe metadata quality/provenance, not scientific reliability. Disable Zotero and webpage comparison for the baseline DOI check: a complete Crossref record should be Verified. arXiv/ISBN may be High without a DOI. Use the fixtures below for Medium, Low and conflicts. Expand Source health or click the confidence badge to inspect missing fields, unavailable checks and provenance.
14. **Conflict review:** Use the conflict fixture with Zotero off and internet available. Expect Crossref vs Webpage title/author/year alternatives and limited confidence. Select Use beside a webpage date: citation should regenerate using 1901. Reopen from History to verify the choice persists. Choosing a value should not erase the discrepancy or make it Verified. DOI conflicts require a fresh lookup. Fresh lookups can replace previously chosen values.
15. **Preferences:** Change default style and confirm immediate effect. Try primary Copy = Full, In-text, Ask every time. Record a different shortcut, e.g. Control–Command–K; test it in TextEdit and Reset afterward. Unsupported plain keystrokes should not replace the shortcut. If registration fails, the previous shortcut remains active.
16. **Provider toggles:** Disable PubMed and submit its labeled ID; expect a disabled-provider explanation. Repeat for arXiv and ISBN, then restore them. Disable/enable webpage comparison and regenerate a DOI; Source health should show skipped/attempted comparison. Existing history is not reverified just by toggling settings.
17. **Custom Zotero/failure:** Optional: enable custom-server mode, save `http://127.0.0.1:1`, and generate the PLOS URL. Expect a visible unavailable Zotero check while other successful metadata still produces a citation. Reject a remote plain-HTTP URL such as `http://example.com`. Turn custom-server mode off afterward to return to automatic mode.
18. **Network/errors:** Disconnect Wi-Fi and attempt a new lookup; expect an error, no fabricated metadata, and a responsive app. Saved history should still format/copy. Test `not a source` through manual paste. Clear with the x button during lookup; a late result should not replace the cleared state.
19. **Interface/animations:** Check centered placement on the display containing the pointer, focused empty search field, Return submission, rounded material panel, fade-in, resize on results/details/quotes, scrolling for long citations, and Escape/outside-click dismissal. Try light/dark appearance. Enable macOS Reduce Motion and compare. Ensure quote editor, source health, conflicts and more-copy menu remain usable without accidentally dismissing the panel.
20. **Menu visibility/login:** Turn off Show menu-bar icon; verify Dock access works, then restore the setting. Enable Launch CiteKit at login; approve macOS Login Items if prompted. With the app at a stable location, sign out/in when convenient and verify it starts. Turn the preference off afterward if undesired. Login behavior still needs manual validation on your Mac.
21. **Privacy behavior:** Copying arbitrary URLs without invoking CiteKit should not open a popup. Highlighting alone should not trigger a lookup. Quotes/history remain local; source lookups still need network access. Complete network-privacy verification requires traffic inspection beyond this basic UI check.

## Controlled confidence/conflict fixtures

From a terminal in the project folder:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Tests/ManualFixtures
```

Keep it running while testing these URLs in CiteKit with Zotero **off**:

| Input | Expected |
| --- | --- |
| `http://127.0.0.1:8765/complete.html` | Medium confidence, metadata present but no DOI or Zotero verification |
| `http://127.0.0.1:8765/missing.html` | Low confidence, missing author/date and other fields |
| `http://127.0.0.1:8765/conflict.html` | Crossref comparison with deliberate title/author/year conflicts; internet required |

These pages are synthetic and clearly labeled. Control-C stops this test-page server. The app's automatic Zotero service is separate and needs no Terminal setup. Delete fixture citations from History when done.

## Not yet available

Automatic browser/PDF source association for quotes, PDF import/page detection, drag-and-drop, article-title search, free-form metadata editing, rich-text clipboard formatting, automatic clipboard monitoring, recent sources inside the menu, bibliography export, projects/tags/favorites, cloud sync and Word/Google Docs integrations.

## Reporting a failed test

Record the test number, exact input, originating app, current preferences, expected result, actual result, and visible error or screenshot. Distinguish “source lookup failed” from “selection could not be read.”
