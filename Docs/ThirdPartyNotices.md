# Third-party resources

Resources were retrieved on 2026-09-24 and are vendored so runtime formatting does not download executable code. SHA-256 hashes are recorded in ResourceChecksums.txt.

- **citeproc-js**, Frank Bennett and contributors: https://github.com/Juris-M/citeproc-js . Source: `master/citeproc.js`. Upstream license offers CPAL 1.0 or AGPL 3.0 or later; see the bundled `CITEPROC-LICENSE`. Preserve upstream attribution and review the selected license's distribution obligations before releasing the combined application.
- **APA Style 7th edition** and **MLA Handbook 9th edition**, Citation Style Language contributors: https://github.com/citation-style-language/styles . Sources: `master/apa.csl`, `master/modern-language-association.csl`. Licensed CC BY-SA 3.0; author credits and license links are embedded in each file. Files are unmodified.
- **CSL English (US) locale**, Citation Style Language contributors: https://github.com/citation-style-language/locales . Source: `master/locales-en-US.xml`; attribution is embedded in the file.

Crossref metadata is retrieved through https://api.crossref.org/works/{doi}. API documentation: https://www.crossref.org/documentation/retrieve-metadata/rest-api/ . CiteKit is not affiliated with Crossref, Zotero, APA or MLA.

## Bundled service in version 0.3

- **Zotero Translation Server 2.0.5**, upstream commit `3a9d17614896fc1fea73d7b880ea79273b605275`: https://github.com/zotero/translation-server . AGPL-3.0-only; source, submodules, lockfile, dependency license files and COPYING are included in `Contents/Resources/Zotero/server`. CiteKit's lifecycle adapter is in `Support/Zotero/managed-server.cjs`. Review combined-app distribution obligations before release.
- **Node.js 24.21.0**, official darwin-arm64 runtime: https://nodejs.org/dist/v24.21.0/node-v24.21.0-darwin-arm64.tar.gz . Archive SHA-256: `bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057`. The complete upstream license is bundled as `Contents/Resources/Zotero/NODE-LICENSE`.
