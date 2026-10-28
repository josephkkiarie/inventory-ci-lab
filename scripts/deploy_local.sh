#!/bin/sh
# Keep the old local container available until the replacement passes health checks.
set -eu

image_tag="${1:?usage: deploy_local.sh IMAGE_TAG}"
live=inventory-live
backup=inventory-previous
had_previous=0
cutover_started=0

rollback() {
    result=$?
    trap - EXIT
    if [ "$result" -ne 0 ] && [ "$cutover_started" -eq 1 ]; then
        echo "Deployment validation failed; restoring previous container" >&2
        if [ "$had_previous" -eq 1 ]; then
            if docker container inspect "$backup" >/dev/null 2>&1; then
                docker rm -f "$live" >/dev/null 2>&1 || true
                docker rename "$backup" "$live" || true
            fi
            docker start "$live" >/dev/null 2>&1 || true
            for attempt in $(seq 1 20); do
                if curl -fsS http://127.0.0.1:5050/health >/dev/null 2>&1; then
                    echo "Previous container restored and healthy" >&2
                    break
                fi
                sleep 1
            done
        else
            docker rm -f "$live" >/dev/null 2>&1 || true
        fi
    fi
    exit "$result"
}
trap rollback EXIT

if docker container inspect "$backup" >/dev/null 2>&1; then
    echo "Refusing deployment: $backup already exists; inspect recovery state" >&2
    exit 1
fi
if docker container inspect "$live" >/dev/null 2>&1; then
    had_previous=1
    cutover_started=1
    docker stop "$live" >/dev/null
    docker rename "$live" "$backup"
fi
cutover_started=1
docker run -d --restart unless-stopped --name "$live" \
    -p 127.0.0.1:5050:5000 "$image_tag" >/dev/null

ready=0
for attempt in $(seq 1 20); do
    if curl -fsS http://127.0.0.1:5050/health 2>/dev/null | grep -q '"status":"ok"'; then
        ready=1
        break
    fi
    sleep 1
done
test "$ready" -eq 1
test "${FORCE_DEPLOY_VALIDATION_FAILURE:-0}" != 1

if [ "$had_previous" -eq 1 ]; then
    docker rm -f "$backup" >/dev/null
fi
echo "Deployment validated: $image_tag"
