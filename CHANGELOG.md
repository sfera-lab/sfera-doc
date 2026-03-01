# Changelog

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
