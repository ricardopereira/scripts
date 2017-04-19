#!/usr/bin/env bash

# Created by Hugo Ferreira <hugo@mindclick.info> on 2014-01-06.
# Copyright (c) 2014 Mindclick. All Rights Reserved.
# Licensed under the MIT License: https://opensource.org/licenses/MIT
readonly BASEDIR=$(cd "$(dirname "$0")" && pwd) # where the script is located
readonly CALLDIR=$(pwd)                         # where it was called from
readonly STATUS_SUCCESS=0                       # exit status for commands

# Script configuration
LC_ALL=C
readonly YNAB_DIR_TEMPLATE="YNAB-$(date +%Y%m%d-%H%M%S)-$$"
readonly YNAB_CSV_HEADER="Date,Payee,Category,Memo,Outflow,Inflow"

# BCP ORDEM
readonly BCP_WATERMARK="Rede:;Millennium BCP"
readonly BCP_SED_CMD='1,13d;$d'  # discard: header = 13 lines; footer = last line
readonly BCP_AWK_DELIM=';'
readonly BCP_AWK_MAPPING='amount=$4; date=$1; payee=$3;'

# BCP CREDIT CARD
readonly BCP_CREDIT_WATERMARK="CARTAO MILLENNIUM BCP"
readonly BCP_CREDIT_SED_CMD='1,11d;$d'  # discard: header = 11 lines; footer = last line
readonly BCP_CREDIT_AWK_DELIM=';'
readonly BCP_CREDIT_AWK_MAPPING='amount=(-$5); date=$2; payee=$3;'

# CGP ORDEM
readonly CGP_WATERMARK="Número de conta:: ,00024861210001"
readonly CGP_SED_CMD='1,6d'  # discard: header = 6 lines; footer = none
readonly CGP_AWK_DELIM=','   # http://backreference.org/2010/04/17/csv-parsing-with-awk/
readonly CGP_AWK_MAPPING='amount=$3; date=$1; payee=$2;'

# Script functions
function usage () {
    echo "
Usage: $(basename $0) [options] source

    -h          this usage help text
    source      file or directory to convert
                ... if a file, converts it as-is
                ... if a directory, converts all files with a .csv extension

Converts files from the CSV format generated by banks to the CSV format required by YNAB.
This script creates a directory with the converted file(s) next to the original ones

Example:
    $ $(basename $0) ~/Downloads/
    File parsed into: ~/Downloads/$YNAB_DIR_TEMPLATE/
    "
    exit ${1:-0}
}

function ask_if_empty () {
    local value="$1"
    local default="$2"
    local message="$3"
    local options="$4"  # pass "-s" for passwords
    if [[ -z "$value" ]]; then
        read $options -p "$message [$default] " value
    fi
    value=$(echo ${value:-$default})
    echo "$value"
}

function convert_dir () {
    local dir="$1"
    if [[ -z "$(ls "$dir"/*.csv 2> /dev/null)" ]]; then
        echo "No files to process in directory."
    else
        find "$dir" -type f -name "*.csv" -maxdepth 1 | while read file; do
            convert_file "$file"
        done
    fi
}

function convert_file () {
    local file="$1"
    
    if is_valid "$BCP_WATERMARK" "$file"; then
        sed -i .tmp -E 's/MMD[0-9]{0,7} //g' "$file"       # remove all the MMD* prefixes
        parse_file "$file" "$BCP_SED_CMD" "$BCP_AWK_DELIM" "$BCP_AWK_MAPPING"
        mv "$file.tmp" "$file"
        
    elif is_valid "$BCP_CREDIT_WATERMARK" "$file"; then
        parse_file "$file" "$BCP_CREDIT_SED_CMD" "$BCP_CREDIT_AWK_DELIM" "$BCP_CREDIT_AWK_MAPPING"
        
    elif is_valid "$CGP_WATERMARK" "$file"; then
        sed -i .tmp -E 's/"(-?[0-9]+),([0-9]+)"/\1.\2/g' "$file"    # convert form "0,00" => 0.00
        parse_file "$file" "$CGP_SED_CMD" "$CGP_AWK_DELIM" "$CGP_AWK_MAPPING"
        mv "$file.tmp" "$file"
        
    else
        echo "File is not a supported bank csv: $file"
    fi
}

function is_valid () {
    local mark="$1"
    local file="$2"
    grep -q "$mark" "$file"     # found = valid; not found = invalid
}

function parse_file () {
    local file="$1"
    local sed_cmd="$2"
    local awk_delim="$3"
    local awk_mapping="$4"
    local tempdir="$(dirname "$file")/$YNAB_DIR_TEMPLATE"
    local targetfile="$tempdir/$(basename "$file")"
    mkdir -p "$tempdir"
    echo $YNAB_CSV_HEADER > "$targetfile"
    sed "$sed_cmd" "$file" | awk -F "$awk_delim" '{
        '"$awk_mapping"'
        if (amount < 0) {
            outflow = substr(amount, 2);
            inflow = "";
        } else {
            outflow = "";
            inflow = amount;
        }
        print date ",\"" payee "\",,," outflow "," inflow;
    }' >> "$targetfile"
    echo File parsed into: "$targetfile"
}

function error_msg () {
    local message=$1
    [[ "$message" ]] && echo $message
    exit 1
}

# Parse command line options
while getopts h option; do
    case $option in
        h) usage ;;
        \?) usage 1 ;;
    esac
done
shift $(($OPTIND - 1));     # take out the option flags

# Validate input parameters
origin=$(ask_if_empty "$1" "$HOME/Downloads" "Enter the file(s) to convert:")
echo Converting: $origin
[[ ! -a "$origin" ]] && error_msg "File or directory does not exist."

# Do the work
if [[ -d "$origin" ]]; then
    convert_dir "$origin"
elif [[ -f "$origin" ]]; then
    convert_file "$origin"
fi
