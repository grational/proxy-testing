#!/bin/bash
# @author          Giuseppe Ricupero
# @contact         giuseppe.ricupero@polito.it
# @external_tools  parallel, mutt, gzip
# @external_files  proxy_testing.conf, trusted-proxy.xml, facebook.token
# @description     this tool is used to test the functionality state of a list
#                  of proxies used by the proxy-manager tool.
#                  Several options are possibles:
#                  [--all|-a]              test all the proxies against a google
#                                          query
#                  [--facebook|-f]         make a facebook query to test them
#                  [--proxy|-p] <proxy_ip> test only the specified proxy
#                  [--url|-u] <url>        specify the url to test against
#                  [--tcp-port|-t] <port>  specify a different port
#                                          number for the proxies
# TODO
# - test external deps (conf, tools and resources)
# -e stops the execution if a command return with an error
# -u treat empty variables as errors (replace ${1} with ${1:-})
# -o pipefail: stop execution of a pipe with error if a command in the chain
# fails
set -euo pipefail
# Change the fields separator from $' \n\t' -> $'\n\t' (space is not a word
# separator anymore)
IFS=$'\n\t'
NL=$'\n'

# INITIALIZATION AND CONF
# -----------------------
SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"
# ----------------------------------------------
# TODO: put all the next line in the conf file
# ----------------------------------------------
PROXY_XML='/store/tomcat/crawlerproxy/webapps/proxy-service/WEB-INF/classes/trusted-proxy.xml'
FB_ACCESS_TOKEN=$(<"${SCRIPT_DIR}"/facebook.token)
WGET_OPTIONS="-t 1 -T 5 --no-check-certificate -qO -"
FB_GRAPH_REQUEST="https://graph.facebook.com/4?access_token=${FB_ACCESS_TOKEN}"
GOOGLE_REQUEST="https://www.google.it/search?q=piadinerie&oq=piadinerie&ie=UTF-8"
PROXY_PORT=80
# ----------------------------------------------
# Aggiungiamo un
REQUEST="${GOOGLE_REQUEST}"

echo '--'
# Without any parameter tests all proxies (read directly from trusted-proxy.xml file)
if [ -z "${1}" ]; then

  while read -r proxy; do
    echo "export https_proxy=http://${proxy}:${PROXY_PORT} && wget ${WGET_OPTIONS} ${REQUEST} >/dev/null"
    export https_proxy="http://${proxy}:${PROXY_PORT}" && wget ${WGET_OPTIONS} "${REQUEST}" >/dev/null
    echo "WGET RETURN CODE: ${?}${NL}--"
  done < <(grep -oP '(?<=tprx:hostname>)[^<\s]+' "${PROXY_XML}" | sort -t'.' -n | uniq)

# Specifing -p
elif [ "${1}" = "-p" ]; then

  proxy="${2}"
  echo "export https_proxy=http://${proxy}:${PROXY_PORT} && wget ${WGET_OPTIONS} ${FB_GRAPH_REQUEST}"
  set +e; export https_proxy="http://${proxy}:${PROXY_PORT}" && wget ${WGET_OPTIONS} "${FB_GRAPH_REQUEST}"
  set -e;
  echo "WGET RETURN CODE: $?"
  echo "--"
fi
