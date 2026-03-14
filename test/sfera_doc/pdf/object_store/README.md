# Azure Blob Storage Testing

This directory contains tests for the Azure Blob Storage adapter using **Azurite**, Microsoft's official Azure Storage emulator.

## Setup

### 1. Start Azurite

Start the Azurite emulator using Docker Compose:

```bash
docker-compose -f docker-compose.test.yml up -d azurite
```

Verify it's running:
```bash
docker ps | grep azurite
```

### 2. Run the tests

Run only the Azure tests:
```bash
mix test --only azure
```

Or run all tests (Azure tests will be skipped if Azurite is not running):
```bash
mix test
```

### 3. Stop Azurite

When you're done testing:
```bash
docker-compose -f docker-compose.test.yml down
```

To also remove the data volume:
```bash
docker-compose -f docker-compose.test.yml down -v
```

## Configuration

The tests use Azurite's default credentials:
- **Account Name**: `devstoreaccount1`
- **Account Key**: `Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==`
- **Blob Endpoint**: `http://127.0.0.1:10000/devstoreaccount1`

These are well-known development credentials and should **never** be used in production.

## Troubleshooting

### Tests are skipped

If you see a message about Azurite not running:
```
⚠️  Azurite not running. Start it with:
   docker-compose -f docker-compose.test.yml up -d azurite
```

Make sure Azurite is started and listening on port 10000.

### Connection refused

If tests fail with connection errors, ensure:
1. Docker is running
2. Port 10000 is not in use by another service
3. Azurite container is healthy: `docker logs sfera_doc_azurite`

### Browse stored blobs

You can use Azure Storage Explorer or any Azure SDK tool configured with the development credentials to browse the test container at:
```
http://127.0.0.1:10000/devstoreaccount1
```
