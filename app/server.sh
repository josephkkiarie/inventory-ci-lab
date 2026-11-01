#!/usr/bin/env bash
# socat starts one copy of this handler for each local TCP connection.
set -u

app_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=app/router.sh
source "$app_dir/router.sh"

IFS=' ' read -r method target protocol || exit 0
protocol=${protocol%$'\r'}
while IFS= read -r header; do
    [[ $header == $'\r' || -z $header ]] && break
done

route "$method" "$target"
case $status in
    200) reason='OK' ;;
    400) reason='Bad Request' ;;
    404) reason='Not Found' ;;
    405) reason='Method Not Allowed' ;;
    *) reason='Internal Server Error' ;;
esac

printf 'HTTP/1.1 %s %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
    "$status" "$reason" "${#body}" "$body"
