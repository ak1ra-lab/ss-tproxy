#! /bin/bash
# helper script to switch ss-redir client config

set -o errexit
set -o pipefail

function usage() {
    cat <<EOF

Usage:
    ./ss-subscribe.sh [-h|--help]             Display this help message
    ./ss-subscribe.sh [pattern]               Interactive mode, the server is selected by the user,
                                              pass optional 'pattern' (any string) to limit the displayed server
    ./ss-subscribe.sh update-subscribe        Non-interactive mode, update the subscription and
                                              apply the latest server subscription to ss-redir.service
                                              according to the 'remarks' value in the '$subscribe_url_json' file

    You must put a valid SIP008 format subscription link in '$subscribe_url_json' file,
    if such file does not exist, execute this script will exit.
    The file format is:
    {
        "url": "https://dler.cloud/subscribe/\$subscribe_token?mu=sip008&type=love",
        "remarks": ""
    }

    You can use tindy2013/subconverter to convert your Shadowsocks subscription link to SIP008 format,
    see: https://github.com/tindy2013/subconverter/blob/master/README-cn.md

Examples:
    ./ss-subscribe.sh
    ./ss-subscribe.sh '香港 IEPL'

EOF
    exit 0
}

function check_command() {
    for command in $@; do
        hash "$command" 2>/dev/null || {
            echo >&2 "Required command '$command' is not installed, Aborting..."
            exit 1
        }
    done
}

function update_subscribe() {
    local subscribe_url=$(jq -r '.url' "$subscribe_url_json")
    if ! echo "$subscribe_url" | grep -qE '^https?://'; then
        usage
    else
        # May be we can check the curl response status code here
        local temp_subscribe_json=$(curl -s "$subscribe_url")
        # In order to avoid overwriting the wrong content directly,
        # we need to check whether the returned content is a legal JSON
        if [ -n "$temp_subscribe_json" ] && jq . <<<"$temp_subscribe_json" >/dev/null 2>&1; then
            jq . <<<"$temp_subscribe_json" >$subscribe_json
        fi
    fi
}

function apply_subscribe() {
    local pattern="$1"

    # test -s FILE, FILE exists and has a size greater than zero
    test -s "$subscribe_json" || update_subscribe
    local selected_items=$(jq --arg pattern "$pattern" '[.[] | select(.remarks | contains($pattern))]' "$subscribe_json")
    local selected_items_length=$(jq length <<<"$selected_items")
    if [ "$selected_items_length" -lt 1 ]; then
        echo "The selected items is empty..."
        exit 0
    fi

    local selected_index=-1
    local selected_item=""
    # When there is only 1 selected_items, skip user selection and apply directly
    if [ "$selected_items_length" -eq 1 ] || [ "$interactive" == "false" ]; then
        selected_index=0
        selected_item=$(jq --argjson index "$selected_index" '.[$index]' <<<"$selected_items")
    else
        # interactive mode, require user selection
        while [ true ]; do
            jq -r '.[].remarks' <<<"$selected_items" | awk '{printf("%3d | %s\n", (NR-1), $0)}'

            read -p "Please select the server according to the index (q to exit): " selected_index
            selected_index=$(echo $selected_index | tr 'A-Z' 'a-z')
            if [ "$selected_index" == "q" ] || [ "$selected_index" == "quit" ]; then
                exit 0
            fi
            if ! [[ "$selected_index" =~ ^[0-9]+$ ]] || [ "$selected_index" -lt 0 ] || [ "$selected_index" -gt "$selected_items_length" ]; then
                echo "Invalid selection, please select again..."
                continue
            else
                selected_item=$(jq --argjson index "$selected_index" '.[$index]' <<<"$selected_items")
                break
            fi
        done
    fi

    # test if the length of $selected_item is zero
    test -z "$selected_item" && return
    local merged_json=$(jq --argjson selected "$selected_item" '. + $selected' "$ss_redir_base_json")

    if ! jq . <<<"$merged_json" | diff - "$ss_redir_json"; then
        jq . <<<"$merged_json" | tee "$ss_redir_json"
        systemctl restart ss-redir.service
    fi

    systemctl status --no-pager ss-redir.service
}

function main() {
    local base_dir=${base_dir:-/etc/shadowsocks-libev}
    local subscribe_json=${subscribe_json:-${base_dir}/subscribe.json}
    local subscribe_url_json=${subscribe_url_json:-${base_dir}/subscribe_url.json}

    local ss_redir_json=${ss_redir_json:-${base_dir}/ss-redir.json}
    local ss_redir_base_json=${ss_redir_base_json:-${base_dir}/ss-redir.base.json}

    local pattern=""
    local interactive=true
    if [ "$#" -gt 0 ]; then
        if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
            usage
        fi

        if [ "$1" == "update" ] || [ "$1" == "update-subscribe" ]; then
            interactive=false
            update_subscribe
            pattern="$(jq -r '.remarks' $subscribe_url_json)"
        else
            pattern="$1"
        fi
    fi

    apply_subscribe "$pattern"
}

check_command awk curl jq

main "$*"
