#!/bin/bash
# @author         Giuseppe Ricupero
# @contact        giuseppe.ricupero@polito.it
# @external_tools parallel, mutt, gzip
# @external_files proxy-testing.conf, trusted-proxy.xml, facebook.token
#                 proxy.list (optional)
# @description    this tool is used to test the functionality state of a list
#                 of proxies (mainly used by the proxy-manager tool in
#                 SeatPG).
#
#                 Several options are possibles:
#               * [--all|-a]              test all the proxies against a google
#                                         query
#               * [--proxy|-p] <proxy_ip> test only the specified proxy
#               * [--facebook|-f]         make a facebook query to test them
#               ? [--url|-u] <url>        specify the url to test against
#               ? [--tcp-port|-t] <port>  specify a different port
#                                         number for the proxies
# BREAKOUT
# -e stops the execution if a command return with an error
# -u treat empty variables as errors (replace ${1} with ${1:-})
# -o pipefail: stop execution of a pipe with error if a command in the chain fails
set -euxo pipefail
# Change the fields separator from $' \n\t' -> $'\n\t' (space is not a word separator anymore)
IFS=$'\n\t'
# Specify a newline (allows to specify an internal newline in echo commands)
NL=$'\n'

# INITIALIZATION AND CONF
# ------------------------
SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(dirname "$(readlink -f "${0}")")"
CONF_FILE="${SCRIPT_DIR}/${SCRIPT_NAME%sh}conf"
if [[ -f "${CONF_FILE}" ]]; then
  source "${CONF_FILE}"
else
  echo >&2 "'${CONF_FILE}' is missing. Aborting."; exit 5
fi

# DEPENDENCIES CHECK
# -------------------
script_deps=(parallel mutt gzip)
for com in "${script_deps[@]}"; do
  command -v "$com" >/dev/null 2>&1 || \
    { echo >&2 "'${com}' executable is required to run ${SCRIPT_NAME}. Aborting."; exit 5; }
done

# CLI PARAMETERS
# ---------------
CLI_DEBUG=''; CLI_VERBOSE=''; CLI_ALL=''; CLI_FB=''
CLI_URL=''; CLI_PROXY=''; CLI_PORT=''; CLI_PROXY_LIST=''
CLI_SHORT='hdvafuptl'; CLI_LONG='help,debug,verbose,all,facebook,url,proxy,tcp-port,proxy-list'
# Handle Command line parameters
CLI_PARSED=$(getopt --options ${CLI_SHORT} --longoptions ${CLI_LONG} --name "$0" -- "$@")
# Add -- at the end of line arguments
eval set -- "${CLI_PARSED}"

usage() {
  echo "${SCRIPT_NAME} usage:"
	echo ' [-h|--help]'
	echo ' [-d|--debug]'
	echo ' [-v|--verbose]'
  echo ' [-a|--all]                   test all the proxies against a google query'
  echo ' [-f|--facebook]              make a facebook query to test them'
  echo ' [-u|--url]        <url>      specify the url to test against'
  echo ' [-p|--proxy]      <proxy_ip> test only the specified proxy'
  echo ' [-t|--tcp-port]   <port>     specify a different port number for the proxies'
  echo ' [-l|--proxy-list] <list>     a newline separated list of proxies (instead of xml)'
}

while true; do
  case "$1" in
    -h|--help)
      usage
      exit 5
      ;;
    -d|--debug)
      CLI_DEBUG='yes'
      shift
      ;;
    -v|--verbose)
      CLI_VERBOSE='yes'
      shift
      ;;
    -a|--all)
      CLI_ALL='yes'
      shift
      ;;
    -f|--facebook)
      CLI_ALL='yes'
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      slog "Parameters error"
      exit 3
      ;;
  esac
done

# LOCAL FUNCTION
# ---------------
ref_array() {
  local varname="$1"
  local export_as="$2"
  local code=$(declare -p "$varname")
  local replaced="${code/$varname/$export_as}"
  eval "${replaced/declare -/declare -g}"
}
nPrint() {
  local tcols=$(tput cols)
  local width=${2}
  [[ $width -gt $tcols ]] && width=$tcols
  printf -- "${1}%.0s" `seq 1 ${width}`; echo
}
slog() {
  local TIMESTAMP="$(date +'%Y-%m-%d %H:%M')"
  local TEXT=''
  if [[ 'x-h1' = "x${1}" ]]; then
    shift; TEXT="[${SCRIPT_NAME}] [${TIMESTAMP}] ${@}"
    echo; nPrint '=' "${#TEXT}"
    echo "${TEXT}"
    nPrint '=' "${#TEXT}"
  elif [[ 'x-h2' = "x${1}" ]]; then
    shift; TEXT="[${SCRIPT_NAME}] [${TIMESTAMP}] ${@}"
    echo; echo "${TEXT}"
    nPrint '-' "${#TEXT}"
  else
    echo "[${SCRIPT_NAME}] [${TIMESTAMP}] ${@}"
  fi
}

function sendEmail() {
  source "$EMAILS_CONF_FILE"
  # Export aarray inside parallel (maybe...)
  local email_subject="$1"
  local email_object="${2:-GenIO process has finished its job}"
  local email_attachment=''
  [[ $# -eq 3 ]] && email_attachment="${3}"

  local user
  for user in "${email_recipients[@]}"
  do
    current_email="${user}@${email_domain}"
    [[ ${CLI_DEBUG} ]] && echo "email_object     -> ${email_object}"
    [[ ${CLI_DEBUG} ]] && echo "email_subject    -> ${email_subject}"
    [[ ${CLI_DEBUG} ]] && echo "current_email    -> ${current_email}"
    [[ ${CLI_DEBUG} ]] && echo "email_attachment -> ${email_attachment}"
    if [[ ${email_attachment} ]]; then
      echo "${email_object}" | mutt -s "${email_subject}" -a "${email_attachment}" -- "${current_email}"
    else
      echo "${email_object}" | mutt -s "${email_subject}" -- "${current_email}"
    fi
  done
}
function mainProcess() {
  #[[ ${CLI_DEBUG} ]] && set -x
  source "$PARAMS_CONF_FILE"
  # input dataset entire path
  local input="${@}"

  local base_inputfile="${input##*/}"
  local itemsets_outfile="${dir_results}/${base_inputfile%genio}itemsets"
  fim_opt_taxonomies="${fim_opt_taxonomies}/${base_inputfile%genio}taxonomies"
  rules_outfile="${dir_results}/${base_inputfile%genio}rules"

  [[ ${CLI_VERBOSE} ]] && slog -h1 "PROCESSING '$base_inputfile'"
  local cmd_fim="gen_fim_all_multi.py ${fim_opt_common} ${fim_opt_taxonomies} ${dir_datasets}/${base_inputfile} ${fim_opt_min_absolute_support} ${fim_opt_max_itemset_size} -o ${itemsets_outfile}"
  local cmd_rules="rules.py ${itemsets_outfile} ${rules_minconf} -o ${rules_outfile}"

  if [[ ${CLI_DEBUG} ]]; then
    ## DEBUG FIM PROCESS
    [[ ${CLI_VERBOSE} ]] && slog -h2 "FIM phase"
    if [[ ! -f "${itemsets_outfile}" ]]; then
      slog $cmd_fim
    else
      slog "'FIM' File ${itemsets_outfile} already exists! Nothing done."
    fi
    ## DEBUG RULES PROCESS
    [[ ${CLI_VERBOSE} ]] && slog -h2 "RULES phase"
    if [[ ! -f "${rules_outfile}" ]]; then
      slog "$cmd_rules"
    else
      slog "'RULES' File ${rules_outfile} already exists! Nothing done."
    fi
  else
    ## FIM PROCESS
    [[ ${CLI_VERBOSE} ]] && slog -h2 "FIM phase"
    if [[ ! -f "${itemsets_outfile}" ]]; then

      slog "FIM START: $cmd_fim"
      local fim_start_timestart="$(date +'%Y-%m-%d %H:%M')"
      gen_fim_all_multi.py $fim_opt_common $fim_opt_taxonomies "${dir_datasets}"/$base_inputfile $fim_opt_min_absolute_support $fim_opt_max_itemset_size -o "${itemsets_outfile}"
      local fim_stop_timestart="$(date +'%Y-%m-%d %H:%M')"
      slog "FIM STOP: $cmd_fim"
    else
      slog "FIM: File ${itemsets_outfile} already exists! Nothing done."
    fi

    ## RULES PROCESS
    [[ ${CLI_VERBOSE} ]] && slog -h2 "RULES phase"
    if [[ ! -f "${rules_outfile}" ]]; then
      slog "RULES START: $cmd_rules"
      local rules_start_timestart="$(date +'%Y-%m-%d %H:%M')"
      rules.py "${itemsets_outfile}" "${rules_minconf}" -o "${rules_outfile}" &> /dev/null
      local rules_stop_timestart="$(date +'%Y-%m-%d %H:%M')"
      slog "RULES STOP: $cmd_rules"
      gzip "${rules_outfile}"
      # sendEmail subject object [attachment]
      local email_subject="[${HOSTNAME}] Rules for ${base_inputfile}"
      local email_object="Rules for input file ${base_inputfile}. ${NL} [fim.py] Supporto minimo: $fim_opt_min_absolute_support ; Max Itemset: $fim_opt_max_itemset_size ${NL}[rules.py]Confidenza minima: $rules_minconf${NL}[ FIM Start @ $fim_start_timestart - FIM Stop @ $fim_stop_timestart] [ RULES Start @ $rules_start_timestart - RULES Stop @ $rules_stop_timestart ]"
      local email_attachment="${rules_outfile}.gz"
      [[ -f "$email_attachment" ]] && sendEmail "$email_subject" "$email_object" "$email_attachment"
    else
      slog "RULES: File ${rules_outfile} already exists! Nothing done."
    fi
  fi
}

# MAIN LOOP
# ---------
if [[ -z ${CLI_SERIAL} ]]; then
  # export to parallel functions and vars of this process
  export -f mainProcess sendEmail slog nPrint
  export SCRIPT_NAME PARAMS_CONF_FILE EMAILS_CONF_FILE CLI_SERIAL CLI_DEBUG CLI_VERBOSE
  slog "Started."
  # -H: follow symbolic links only when processing command lines
  find -H "${dir_datasets}" -type f -name "*.genio" | parallel "${opt_parallel}" 'mainProcess {}'
  slog "Finished."
else
  find -H "${dir_datasets}" -type f -name "*.genio" | while read infile; do
    mainProcess "$infile"
  done
fi

# FB parameter needed to access pages' data
FB_ACCESS_TOKEN="?access_token=$(<"${SCRIPT_DIR}"/facebook.token)"
REQUEST="${GOOGLE_REQUEST}"





# ----------------------------------------------
# The actual business code
# ----------------------------------------------
echo '--'
# Without any parameter tests all proxies (read directly from trusted-proxy.xml file)
if [[ -z "${1:-}" ]]; then

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
