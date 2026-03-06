# Changelog

## [0.0.2] 2026-03-06
### Added
- `.iex.exs` development helper that auto-starts `SferaDoc.Dev.Repo` when using Ecto storage adapter
- `SferaDoc.Dev.Repo` module for development database connection
- Comprehensive test suite for `SferaDoc.Cache.ParsedTemplate` covering cache operations, TTL expiration, and edge cases

### Fixed
- Changed PDF assigns hashing from MD5 to SHA-256 for better collision resistance
- Fixed ChromicPDF adapter to remove invalid `:output` option and properly decode base64-encoded PDFs
- Fixed `SferaDoc.Renderer.render/3` to return `{:ok, pdf_binary}` instead of telemetry result

### Changed
- Refactored `SferaDoc.Cache.ParsedTemplate` for better code organization and removed unnecessary documentation
- Added debug logging for PDF size when rendering with ChromicPDF
- Updated README:
  - Added link to Development Guidelines wiki page under Contributing section
  - Updated features to describe two-tier PDF storage architecture
  - Changed "hot cache" terminology to "cache" for clarity
- Updated module documentation:
  - Simplified and shortened main module docs while preserving all examples
  - Added explicit explanation of storage backends (templates vs PDFs)
  - Reorganized PDF caching section into "Two-Tier PDF Storage"
  - Added comprehensive pluggable adapter documentation for storage backends, template engines, PDF engines, and object stores
  - Moved object store adapter documentation to Pluggable Engines section for consistency

## [0.0.1] 2026-02-27

### Added
- Initial release of SferaDoc, a PDF generation library for Elixir
- Versioned Liquid template management with create, update, list, activate, and delete operations
- Template parsing with `solid` and ETS-based parsed template caching
- Chrome-based PDF rendering via `chromic_pdf`
- Pluggable template storage adapters: Ecto, Redis, and ETS
- Optional two-tier PDF storage: hot cache (Redis or ETS) plus durable object store (S3, Azure Blob, or file system)
- Required variable schema validation before rendering
- Telemetry events for render start, stop, and exception
