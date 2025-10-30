#!/usr/bin/env bash

# Enable strict error handling for debugging only
# set -euo pipefail

function vault_upload {
    local DOMAIN="${1}"
    local KEYFILE="${2}"
    local CERTFILE="${3}"
    local FULLCHAINFILE="${4}"
    local CHAINFILE="${5}"

    local MAIN=$(<<<"${DOMAIN}" grep -oP '[^\.]+\.[^\.]+$')
    local HOST="${DOMAIN/.${MAIN}/}"

    if [[ "${HOST}" == "" ]]; then
        local STORE=secret/dehydrated/${MAIN}/${HOST}
    else
        local STORE=secret/dehydrated/${MAIN}/wildcard
    fi

    local TOKEN=$(
        curl -s -X POST \
            -d "{\"role_id\":\"SNIP\",\"secret_id\":\"SNIP\"}" \
            https://vault.example.com/v1/auth/approle/login | jq -r .auth.client_token
    )

    curl -s -X POST \
        -H "X-Vault-Token: ${TOKEN}" \
        -d @<(
            jq -n \
                --arg cert "$(< ${CERTFILE} )" \
                --arg key "$(< ${KEYFILE} )" \
                --arg chain "$(< ${CHAINFILE} )" \
                --arg fullchain "$(< ${FULLCHAINFILE} )" \
                --arg timestamp "${TIMESTAMP}" \
                '{cert:$cert,key:$key,chain:$chain,fullchain:$fullchain}'
        ) \
        https://vault.example.com/v1/${STORE}
}

function deploy_challenge {
    local DOMAIN="${1}"
    local TOKEN_FILENAME="${2}"
    local TOKEN_VALUE="${3}"

    lexicon cloudflare create ${DOMAIN} TXT \
        --name="_acme-challenge.${DOMAIN}." \
        --content="${TOKEN_VALUE}" \
        --auth-username="devops@example.com" \
        --auth-token="SNIP"

    sleep 10

    :
}

function clean_challenge {
    local DOMAIN="${1}"
    local TOKEN_FILENAME="${2}"
    local TOKEN_VALUE="${3}"

    lexicon cloudflare delete ${DOMAIN} TXT \
        --name="_acme-challenge.${DOMAIN}." \
        --content="${TOKEN_VALUE}" \
        --auth-username="devops@example.com" \
        --auth-token="SNIP"

    :
}

function deploy_cert {
    local DOMAIN="${1}"
    local KEYFILE="${2}"
    local CERTFILE="${3}"
    local FULLCHAINFILE="${4}"
    local CHAINFILE="${5}"

    vault_upload "${@}"

    :
}

function unchanged_cert {
    local DOMAIN="${1}"
    local KEYFILE="${2}"
    local CERTFILE="${3}"
    local FULLCHAINFILE="${4}"
    local CHAINFILE="${5}"

    vault_upload "${@}"

    :
}

function invalid_challenge() {
    local DOMAIN="${1}"
    local RESPONSE="${2}"

    :
}

exit_hook() {
  :
}

startup_hook() {
  :
}

HANDLER="${1}"
shift

if [ -n "$(type -t ${HANDLER})" ] && [ "$(type -t ${HANDLER})" = function ]; then
  $HANDLER "${@}"
fi
