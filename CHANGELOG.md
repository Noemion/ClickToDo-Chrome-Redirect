# Changelog

## 0.1.1

- Publish versioned GitHub Releases with matching tags, a standalone BAT and SHA-256 checksum.
- Show the version in the BAT title/banner and add `/version`.
- Report the script, installed executable and rollback executable versions separately in status.
- Generate EXE version metadata from the root `VERSION` file; identify unversioned older builds as legacy.
- Add detailed source comments and checks for version consistency.

## 0.1.0

- Consolidated the previously separate installation and default-search update scripts into one self-contained BAT.
- Forward the exact Edge helper path to Chrome without reinstalling Edge.
- Convert Bing web-search URLs into Chrome profile default-engine searches.
- Add upgrade backup, program rollback, uninstall-state restoration and status diagnostics.
- Include C# source, a repeatable BAT generator, Windows self-tests and GitHub Actions validation.
- Document the user-verified environment, helper-wide interception and compatibility limitations.
