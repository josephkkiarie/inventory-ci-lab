#!/usr/bin/env bash
# Route one HTTP request. This file is sourced by the socket handler and tests.

readonly ROUTER_ITEM='{"id":1,"name":"router","stock":8}'
readonly SWITCH_ITEM='{"id":2,"name":"switch","stock":3}'

route() {
    local method=$1 target=$2 path query threshold digits version item_id
    status=200
    body=''

    if [[ $method != GET ]]; then
        status=405
        body='{"error":"method not allowed"}'
        return
    fi

    path=${target%%\?*}
    query=''
    if [[ $target == *\?* ]]; then
        query=${target#*\?}
    fi

    case $path in
        /)
            version=${APP_VERSION:-dev}
            if [[ ! $version =~ ^[a-zA-Z0-9._-]+$ ]]; then
                version=dev
            fi
            body="{\"service\":\"inventory-api\",\"version\":\"$version\",\"status\":\"running\"}"
            ;;
        /health)
            body='{"status":"ok"}'
            ;;
        /api/items)
            body="{\"items\":[$ROUTER_ITEM,$SWITCH_ITEM]}"
            ;;
        /api/items/low-stock)
            if [[ ! $query =~ ^threshold=([0-9]+)$ ]]; then
                status=400
                body='{"error":"threshold must be an integer from 0 to 100"}'
                return
            fi
            digits=${BASH_REMATCH[1]}
            while [[ ${#digits} -gt 1 && $digits == 0* ]]; do
                digits=${digits#0}
            done
            if [[ ${#digits} -gt 3 ]] || (( 10#$digits > 100 )); then
                status=400
                body='{"error":"threshold must be an integer from 0 to 100"}'
                return
            fi
            threshold=$((10#$digits))
            body='{"items":['
            if (( threshold > 8 )); then
                body+=$ROUTER_ITEM
            fi
            if (( threshold > 3 )); then
                if [[ $body != '{"items":[' ]]; then
                    body+=,
                fi
                body+=$SWITCH_ITEM
            fi
            body+=']}'
            ;;
        /api/items/*)
            item_id=${path#/api/items/}
            if [[ ! $item_id =~ ^[0-9]+$ ]]; then
                status=404
                body='{"error":"item not found"}'
                return
            fi
            while [[ ${#item_id} -gt 1 && $item_id == 0* ]]; do
                item_id=${item_id#0}
            done
            case $item_id in
                1) body=$ROUTER_ITEM ;;
                2) body=$SWITCH_ITEM ;;
                *) status=404; body='{"error":"item not found"}' ;;
            esac
            ;;
        *)
            # shellcheck disable=SC2034  # Read by the server and test callers.
            status=404
            body='{"error":"not found"}'
            ;;
    esac
}
