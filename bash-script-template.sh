#!/usr/bin/env bash

# MIT License
#
# Copyright (c) 2025 Jinesh Choksi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Changes:
#    v0.0.1, 22 Jan 2025, Initial release
#    v0.0.2, 23 Jan 2025, Logging issue fixed

# * External dependencies: basename, dirname, tput
# * Environment variables:
#   - LOG_VERBOSITY: Set to 0=err, 1=wrn, 2=inf, 3=dbg
#   - NO_COLOR: Set to any value to disable colors

set -o errexit      # -e: Exit on error. Append "|| true" if you expect an error.
set -o errtrace     # -E: Exit on error inside any functions or sub shells.
set -o noclobber    # Use the '>|' redirection operator to overwrite a file.
set -o nounset      # -u: Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR.
set -o pipefail     # Use last non-zero exit code in a pipeline.

#-------------------------------------------------------------------------------
# Variables
#-------------------------------------------------------------------------------

# Script wide global variables
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
script_name=$(basename "${BASH_SOURCE[0]}")
script_orig_cwd="${PWD}"
script_params="$*"                         # the IFS expansion of all positional parameters, $1 $2 $3 ...
script_verbosity="${LOG_VERBOSITY:-2}"     # 0=err, 1=wrn, 2=inf, 3=dbg
script_version="0.0.2"
script_log_lvl=()

# Set up colors by default. Users that prefer to have plain, non-colored text
# output can export NO_COLOR=1 to their shell’s environment to disable colors.
if [[ -t 1 && -z "${NO_COLOR:-}" && "$(tput colors 2>/dev/null || echo -1)" -ge 8 ]]; then
  cap_bold="$(tput bold 2>/dev/null || true)"
  cap_sgr0="$(tput sgr0 2>/dev/null || true)"
  cap_setaf_red="${cap_sgr0}$(tput setaf 1 2>/dev/null || true)${cap_bold}"
  cap_setaf_yellow="${cap_sgr0}$(tput setaf 3 2>/dev/null || true)${cap_bold}"
  cap_setaf_white="${cap_sgr0}$(tput setaf 7 2>/dev/null || true)${cap_bold}"
  cap_setaf_darkgray="${cap_sgr0}$(tput setaf 0 2>/dev/null || true)${cap_bold}"
  script_log_lvl[0]="${cap_setaf_red}ERROR${cap_sgr0}"
  script_log_lvl[1]="${cap_setaf_yellow}WARN ${cap_sgr0}"
  script_log_lvl[2]="${cap_setaf_white}INFO ${cap_sgr0}"
  script_log_lvl[3]="${cap_setaf_darkgray}DEBUG${cap_sgr0}"
  unset cap_bold cap_sgr0 cap_setaf_red cap_setaf_yellow cap_setaf_white \
    cap_setaf_darkgray
else
  script_log_lvl[0]="ERROR"
  script_log_lvl[1]="WARN "
  script_log_lvl[2]="INFO "
  script_log_lvl[3]="DEBUG"
fi

# Make global variables read only
readonly script_dir script_name script_orig_cwd script_params script_version \
  script_log_lvl

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------

function __log() {
  local -r lvl="${1}"  # No validation! Meant to only be called by log_* funcs
  shift
  if [ "${script_verbosity}" -ge "${lvl}" ]; then
    printf '%(%Y-%m-%d %H:%M:%S)T %-5s %s %b\n' -1 "${script_log_lvl[${lvl}]}" \
      "${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}" "$*"
  fi
}

function log_err() { __log "0" "${@}"; }

function log_inf() { __log "2" "${@}"; }

function log_wrn() { __log "1" "${@}"; }

function log_dbg() { __log "3" "${@}"; }

function parse_params() {

  log_dbg "Parsing command line parameters: [${script_params}]"

  # Uncomment if script has mandatory options or arguments
  # [[ $# -eq 0 ]] && script_usage

  local opt=""
  local arg_verbosity=""

  # Long options can be parsed by the standard getopts builtin as "arguments"
  # to the - "option". Source: http://stackoverflow.com/a/28466267/7666
  while getopts hv:-: opt; do     # allow -a, -b with arg, -c, and -- "with arg"
    if [ "${opt}" = "-" ]; then   # long option: reformulate opt and OPTARG
      opt="${OPTARG%%=*}"         # extract long option name
      OPTARG="${OPTARG#"${opt}"}" # extract long option argument (may be empty)
      OPTARG="${OPTARG#=}"        # if long option argument, remove assigning `=`
    fi
    log_dbg "Option: [${opt}], Option Argument: [${OPTARG:-}]"
    case "${opt}" in
      h | help      ) script_usage ;;
          version   ) echo "v${script_version}"; exit 0 ;;
      v | verbosity )
                    if [[ -z "${OPTARG}" ]]; then
                      log_err "No arg for --${opt} option";
                      exit 2;
                    fi
                    arg_verbosity="${OPTARG}";
                    ;;
      \?            ) exit 2 ;;  # bad short option (error reported via getopts)
      *             ) log_err "Illegal option --${opt}"; exit 2 ;;  # bad long option
    esac
  done
  shift $((OPTIND-1)) # remove parsed options and args from ${@} list

  if [ -n "${arg_verbosity}" ]; then
    if [ "${arg_verbosity}" -ge 0 ] && [ "${arg_verbosity}" -le 3 ]; then
      script_verbosity="${arg_verbosity}"
    else
      log_err "Verbosity must be either 0,1,2 or 3"
      exit 2
    fi
  fi
}

function script_trap_exit() {
  local exit_code="${1}"
  trap - SIGINT SIGTERM ERR EXIT
  log_dbg "### SCRIPT ENDED ### - Exit code: [${exit_code}]"
}

function script_trap_err() {
  local exit_code="${1}"
  log_err "***** Abnormal termination of script *****"
  log_dbg "Script name/version = ${script_name} v${script_version}"
  log_err "Script params       = [${script_params}]"
  log_err "Script dir          = ${script_dir}"
  log_err "Script orig cwd     = ${script_orig_cwd}"
  log_err "Script cwd          = ${PWD}"
  log_err "Exit status code    = [${exit_code}]"
  log_err "Call stack:"
  log_err "| at: ${BASH_COMMAND}, $(basename "${BASH_SOURCE[1]}"), line ${BASH_LINENO[0]}"
  if [ ${#FUNCNAME[@]} -gt 2 ]; then
    local indentation lvl
    for ((lvl=1; lvl<${#FUNCNAME[@]}-1; lvl++)); do
      indentation="$(printf '|%*s' ${lvl} '')"
      log_err "${indentation} at: ${FUNCNAME[${lvl}]}(), $(basename "${BASH_SOURCE[${lvl}+1]}"), line ${BASH_LINENO[${lvl}]}"
    done
  fi
  exit "${exit_code}"
}

function script_usage() {
    cat << EOF
$script_name v${script_version}, a template to write better Bash scripts
Usage: $script_name [OPTION] ...

Options:
  -h,   --help           Display this help and exit.
  -v n, --verbosity=n    Set log verbosity. 0=err, 1=wrn, 2=inf(default), 3=dbg
        --version        Display script version.

EOF
  exit 0
}

function main() {
  trap 'script_trap_err "${?}"' ERR
  trap 'script_trap_exit "${?}"' EXIT

  log_dbg "### SCRIPT STARTED ###"
  log_dbg "Script name/version = ${script_name} v${script_version}"

  parse_params "${@}"
}

main "${@}"
