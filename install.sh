#! /bin/bash
# helper script to setup ss-tproxy and shadowsocks-libev
# only tested on Debian 12 (bookworm)

if [ $(id -u) -ne 0 ]; then
    echo "This script can only be run as root"
    exit 1
fi

function check_command() {
    for command in $@; do
        hash "$command" 2>/dev/null || {
            echo >&2 "Required command '$command' is not installed, Aborting..."
            exit 1
        }
    done
}

function ensure_ip_forward() {
    # enable ip_forward
    echo 'net.ipv4.ip_forward=1' | tee /etc/sysctl.d/99-ip-forward.conf
    sysctl -p
}

function ensure_xt_tproxy() {
    # load xt_TPROXY at start
    echo 'xt_TPROXY' | tee /etc/modules-load.d/90-xt-tproxy.conf
    modprobe xt_TPROXY
}

function apt_install() {
    apt-get update
    apt-get install -y \
        bash \
        curl \
        dnsmasq \
        gcc \
        git \
        iproute2 \
        ipset \
        iptables \
        jq \
        libc6-dev \
        make \
        simple-obfs \
        shadowsocks-libev \
        vim

    systemctl stop shadowsocks-libev.service
    systemctl disable shadowsocks-libev.service

    systemctl stop dnsmasq.service
    systemctl disable dnsmasq.service
}

function git_clone() {
    local repo_url="$1"
    local repo_dir="$2"

    if [ -d "${repo_dir}" ]; then
        pushd "${repo_dir}" && git pull && popd
    else
        git clone "${repo_url}" "${repo_dir}"
    fi
}

function git_install() {
    local repo_url="$1"
    local repo_dir="$2"

    local program=${repo_dir#${DIR}/}
    if ! hash "$program" 2>/dev/null; then
        git_clone "${repo_url}" "${repo_dir}"

        pushd "${repo_dir}"
        make clean && make && make install
        popd
    fi
}

function main() {
    ensure_ip_forward
    ensure_xt_tproxy

    apt_install

    DIR=$HOME/ss-tproxy
    test -d "${DIR}" || mkdir -v -p "${DIR}"

    pushd "${DIR}"

    git_install https://github.com/zfl9/chinadns-ng "${DIR}/chinadns-ng"
    # git_install https://github.com/zfl9/dns2tcp "${DIR}/dns2tcp"
    # git_install https://github.com/zfl9/ipt2socks "${DIR}/ipt2socks"

    git_clone https://github.com/ak1ra-lab/ss-tproxy "${DIR}/ss-tproxy"

    pushd "${DIR}/ss-tproxy"

    git checkout ss-redir

    install ss-tproxy /usr/local/sbin
    install -d /etc/ss-tproxy
    install -m 644 *.conf *.txt *.ext /etc/ss-tproxy
    install -m 644 ss-tproxy.service /etc/systemd/system
    install -m 644 ss-tproxy-rules-update.service /etc/systemd/system
    install -m 644 ss-tproxy-rules-update.timer /etc/systemd/system

    install -m 644 shadowsocks/ss-redir.service /etc/systemd/system
    install -m 644 shadowsocks/ss-redir.base.json /etc/shadowsocks-libev

    install -m 755 shadowsocks/ss-subscribe.sh /usr/local/sbin
    install -m 644 shadowsocks/ss-subscribe-update.service /etc/systemd/system
    install -m 644 shadowsocks/ss-subscribe-update.timer /etc/systemd/system

    systemctl daemon-reload
    systemctl enable ss-tproxy.service
    systemctl enable ss-tproxy-rules-update.timer
    systemctl enable ss-redir.service
    systemctl enable ss-subscribe-update.timer

    popd

    popd
}

check_command apt-get

main $@
