# Inventory API - Jenkins CI/CD lab on Ubuntu WSL2

This repository is the lab application and pipeline. Jenkins runs as a native Ubuntu service; Docker Desktop supplies the Linux container engine through WSL integration. Keep the repository in `~/projects`, not under `/mnt/c`.

## Architecture

```text
Local Git or GitHub main branch
          |
          v
Jenkins on Ubuntu WSL2 (:8080, localhost only)
  Checkout -> Unit tests -> Ruff -> Docker build -> Candidate smoke test
                                                 -> Local deployment/validation
                   |                                  |
                   v                                  v
       inventory-candidate                    inventory-live
       127.0.0.1:5051 -> :5000              127.0.0.1:5050 -> :5000
```

The host port is `5050`; port `5000` belongs to the container. Docker forwards traffic from `127.0.0.1:5050` to the process listening on port `5000` inside the container. The binding keeps the application local to this PC.

## Prerequisites and setup

Use Ubuntu 24.04 under WSL2 with systemd, Java 21, Git, Python 3.12, `python3-venv`, and Docker Desktop with WSL integration enabled for **Ubuntu-24.04**. Install Jenkins LTS from the official Jenkins apt repository (see the companion lab PDF). Bind Jenkins to `127.0.0.1:8080`, complete its setup with a named local administrator, and install Pipeline, Git, and JUnit plugins. Never put passwords or tokens in this repository.

From a fresh clone in the Ubuntu home filesystem:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest -v
.venv/bin/ruff check app tests
docker build -t inventory-api:local .
```

The developer requirements file includes the production requirements, pytest, and Ruff. The Dockerfile installs **only** `requirements.txt`, copies only `app/`, and runs as UID 10001. `.dockerignore` excludes virtual environments, tests, reports, keys, and local secret files from the build context.

## API

| Request | Result |
| --- | --- |
| `GET /` | Service name, version, running status |
| `GET /health` | `{"status":"ok"}` |
| `GET /api/items` | All inventory items |
| `GET /api/items/1` | Item 1, or JSON 404 for unknown ID |
| `GET /api/items/low-stock?threshold=4` | Items with stock strictly below 4 |

`threshold` must appear exactly once and contain an unsigned integer from 0 through 100. Missing, repeated, negative, fractional, and non-numeric values receive HTTP 400 with a JSON error. At threshold 3, an item with stock 3 is excluded.

To inspect a local image manually:

```bash
docker run -d --name inventory-manual -p 127.0.0.1:5050:5000 inventory-api:local
curl -i http://127.0.0.1:5050/health
curl -i 'http://127.0.0.1:5050/api/items/low-stock?threshold=4'
docker exec inventory-manual id -u
docker rm -f inventory-manual
```

## Pipeline and deployment

Create a Jenkins Pipeline job using **Pipeline script from SCM**, Git branch `*/main`, and script path `Jenkinsfile`. Use a local Git URL for an isolated lab or a GitHub URL after publishing is approved. The pipeline checks out source, runs pytest and publishes JUnit XML, runs Ruff as a separate stage, builds the non-root image, starts a temporary candidate on localhost port 5051, and deploys to localhost port 5050 only after earlier stages pass. The candidate is always removed.

`scripts/deploy_local.sh` preserves the previous `inventory-live` container as `inventory-previous` during cutover. It starts and validates the replacement before deleting the backup. If the replacement fails to start or validate, it removes the replacement, renames and restarts the previous container, and exits with failure. A pre-existing backup stops a new deployment so an unresolved recovery state is not overwritten. There is a short outage while the old container stops and the new one starts; in-flight requests may fail during this interval. This is a local teaching design, not zero-downtime production deployment.

To demonstrate recovery with an existing live container:

```bash
sh scripts/deploy_local.sh inventory-api:local
docker inspect -f '{{.Id}}' inventory-live
FORCE_DEPLOY_VALIDATION_FAILURE=1 sh scripts/deploy_local.sh inventory-api:local
docker inspect -f '{{.Id}}' inventory-live
curl -fsS http://127.0.0.1:5050/health
```

The forced command should fail while the two IDs match and `/health` still succeeds. If recovery itself fails, inspect `docker ps -a`, `docker logs inventory-live`, and `inventory-previous` before trying again. Do not delete `inventory-previous` until the live service is confirmed healthy.

## Security and troubleshooting

Jenkins access to the Docker socket is effectively root-level access to the host. Limit it to a personal isolated lab. A safer production design uses a separate ephemeral build agent with narrowly scoped permissions and an isolated builder, plus a deployment controller with its own credentials. No GitHub credential belongs in `Jenkinsfile`.

If Jenkins checkout fails, verify repository access, branch `main`, and the Git plugin. If tests fail, inspect JUnit and stop before image build. If Docker access fails, check Docker Desktop WSL integration and the Jenkins service account's socket permissions. If smoke tests fail, check `docker logs inventory-candidate` and port 5051. If JUnit is empty, check `reports/pytest.xml`. Avoid exposing Jenkins or the API to a public network.
