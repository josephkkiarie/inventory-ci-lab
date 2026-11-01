# Inventory API - Jenkins CI/CD lab on Ubuntu WSL2

This revision implements the inventory API and its tests in Bash. Jenkins runs as a native Ubuntu service and invokes shell steps. Docker Desktop supplies the container engine through WSL integration. Keep the checkout in `~/projects`, not under `/mnt/c`.

**Assignment note:** The supplied student starter used Flask and pytest. This shell version follows the later instruction to use Bash for the API and tests, so confirm that the instructor accepts a language change before submitting it as the official starter solution.

## Architecture

```text
GitHub main -> Jenkins SCM checkout
  -> Bash unit tests + JUnit XML -> ShellCheck -> Docker build
  -> candidate smoke test on 127.0.0.1:5051
  -> local deployment on 127.0.0.1:5050 with rollback
```

The container runs a small Bash HTTP handler using `socat` for TCP connections. The handler reads one request, calls `app/router.sh`, writes JSON, and closes the connection. The host's port 5050 forwards to port 5000 inside the container. The image runs as UID 10001.

## Prerequisites and local checks

Use Ubuntu 24.04 under WSL2 with systemd, Bash, Git, ShellCheck, and Docker Desktop WSL integration. Jenkins needs the Pipeline, Git, JUnit, and Timestamper plugins. Bind Jenkins to `127.0.0.1:8080`; never publish it publicly.

From the checkout in Ubuntu:

```sh
bash tests/test_api.sh
bash -n app/*.sh tests/*.sh
sh -n scripts/*.sh
shellcheck app/*.sh tests/*.sh scripts/*.sh
docker build -t inventory-api:local .
docker run -d --name inventory-manual -p 127.0.0.1:5050:5000 inventory-api:local
curl -i http://127.0.0.1:5050/health
curl -i 'http://127.0.0.1:5050/api/items/low-stock?threshold=4'
docker exec inventory-manual id -u
docker rm -f inventory-manual
```

The Bash unit tests write `reports/test-results.xml` for Jenkins JUnit publication. ShellCheck is a separate pipeline gate before image build. The Dockerfile installs only Bash and socat and copies only `app/`; `.dockerignore` excludes reports, tests, secrets, and development files from the image build context.

## API

| Request | Result |
| --- | --- |
| `GET /` | Service name, version, running status |
| `GET /health` | `{"status":"ok"}` |
| `GET /api/items` | Both inventory items |
| `GET /api/items/1` | Item 1; an unknown ID returns JSON 404 |
| `GET /api/items/low-stock?threshold=4` | Items with stock strictly below 4 |

`threshold` must appear exactly once and contain an unsigned integer from 0 through 100. Missing, repeated, negative, fractional, and non-numeric values receive HTTP 400 with a JSON error. At threshold 3, an item with stock 3 is excluded.

## Jenkins and deployment

Configure `InventoryPipeline` as **Pipeline script from SCM** using `https://github.com/josephkkiarie/inventory-ci-lab.git`, branch `*/main`, and script path `Jenkinsfile`. The pipeline checks out source, runs the Bash tests, publishes JUnit XML, runs ShellCheck, builds the non-root image, smoke tests a temporary candidate, and deploys only after earlier stages pass. The candidate is always removed.

`scripts/deploy_local.sh` preserves the previous `inventory-live` container as `inventory-previous` during cutover. It validates the replacement before deleting the backup. On failure, it removes the replacement, renames and restarts the previous container, and exits with failure. A pre-existing backup stops deployment for manual review. This teaching design has a brief outage during cutover.

To check rollback with an existing live container:

```sh
docker inspect -f '{{.Id}}' inventory-live
FORCE_DEPLOY_VALIDATION_FAILURE=1 sh scripts/deploy_local.sh inventory-api:local
docker inspect -f '{{.Id}}' inventory-live
curl -fsS http://127.0.0.1:5050/health
```

The forced command should fail, the two container IDs should match, and `/health` should still succeed. Inspect `docker ps -a` and logs if recovery itself fails.

## Security

Jenkins access to the Docker socket is effectively host root-level control. Restrict it to this isolated training PC. No GitHub token belongs in the repository or Jenkinsfile. The application and Jenkins bind only to loopback host ports.
