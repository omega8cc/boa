#!/usr/bin/env bash
# https://github.com/lukas2511/dehydrated/blob/master/docs/examples/hook.sh

set -eu -o pipefail

deploy_challenge() {
		local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
		echo ""
		echo "Add the following to the zone definition of ${1}:"
		echo "_acme-challenge.${1}. IN TXT \"${3}\""
		echo ""
		echo -n "Press enter to continue..."
		read tmp
		echo ""
}

clean_challenge() {
		local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
		echo ""
		echo "Now you can remove the following from the zone definition of ${1}:"
		echo "_acme-challenge.${1}. IN TXT \"${3}\""
		echo ""
		echo -n "Press enter to continue..."
		read tmp
		echo ""
}

deploy_cert() {
		local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"
		echo ""
		echo "deploy_cert()"
		echo ""
}

unchanged_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"
		echo ""
		echo "unchanged_cert()"
		echo ""
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"
		echo ""
		echo "invalid_challenge()"
		echo "${1}"
		echo "${2}"
		echo ""
}

request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE="${3}"
		echo ""
		echo "request_failure()"
		echo "${1}"
		echo "${2}"
		echo "${3}"
		echo ""
}

exit_hook() {
		echo ""
		echo "done"
		echo ""
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|exit_hook)$ ]]; then
  "$HANDLER" "$@"
fi
