#!/bin/bash

function echo_colour()
{
    str=""
    case "$2" in
        "g") str+="\033[32m" ;;
        "y") str+="\033[31m" ;;
        "r") str+="\033[33m" ;;
    esac
    str+="$1\033[0m"
    echo -e $str
}

print_banner()
{
    echo -e "GitGet - @TaconeoMental"
}

help_msg()
{
    echo "Usage: $0 -r [REPO-URL] -o [OUTPUT-DIR]"
    exit 1
}

while getopts ":o:r:" opt
do
    case "$opt" in
        o) git_dir="$OPTARG" ;;
        r) repo_url="$OPTARG" ;;
        \:)
            print_banner
            echo_colour "Option '-$OPTARG' needs an argument" "r"
            help_msg
            exit 1
            ;;
    esac >&2
done

if [ -z "$git_dir" ] || [ -z "$repo_url" ]
then
    print_banner
    help_msg
fi

# Helpers
function grep_hashes()
{
    local out=$(grep -av "\.git" - | grep -Eoa "[a-f0-9]{2}[a-f0-9]{38}" | sort -u)
    echo $out
}

# Globals
GIT_DIR="${git_dir}/.git/"
HASHES=()

function download_initial()
{
    local STATIC=()
    STATIC+=('HEAD')
    STATIC+=('objects/info/packs')
    STATIC+=('description')
    STATIC+=('config')
    STATIC+=('COMMIT_EDITMSG')
    STATIC+=('index')
    STATIC+=('packed-refs')
    STATIC+=('refs/heads/master')
    STATIC+=('refs/remotes/origin/HEAD')
    STATIC+=('refs/stash')
    STATIC+=('logs/HEAD')
    STATIC+=('logs/refs/heads/master')
    STATIC+=('logs/refs/remotes/origin/HEAD')
    STATIC+=('info/refs')
    STATIC+=('info/exclude')
    STATIC+=('/refs/wip/index/refs/heads/master')
    STATIC+=('/refs/wip/wtree/refs/heads/master')

    for file in "${STATIC[@]}"
    do
        download_file $file
    done
    HASHES=($(echo "${HASHES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    for h in "${HASHES[@]}"
    do
        download_hash $h
    done
}

function download_file()
{
    local file_path="$GIT_DIR$1"

    local response=$(curl -s "$repo_url/$1" --create-dirs -o $file_path)
    local status_code="${response:${#response}-3}"
    if grep -Eiq "<\s*\!DOCTYPE\s+html" $file_path >/dev/null || [[ "$status_code" =~ "(400|301)" ]];
    then
    	echo_colour "[-] $1" "r"
        rm $file_path
        return
    fi
    echo_colour "[+] Downloaded $1" "g"
    for h in $(cat $file_path | grep_hashes | tr '\n' ' ')
    do
        HASHES+=($h)
    done
}

function download_hash()
{
    local g_hash path
    g_hash="$1"
    path="objects/${g_hash:0:2}/${g_hash:2}"
    download_file $path
}

function get_fsck_hashes()
{
    local fsck_out=$(git --git-dir=$GIT_DIR fsck |& grep_hashes)
    echo $fsck_out
}

function get_reset_hashes()
{
    local reset_out=$(git reset --hard HEAD |& grep_hashes)
    echo $reset_out
}

function recursive_download()
{
    # $1: hash gen
    local out=$($1)
    while true;
    do
        if [ -z "$out" ];
        then
            break
        fi
        for g_hash in $out
        do
            if [[ ! " ${HASHES[*]} " =~ " ${g_hash} " ]];
            then
                HASHES+=($g_hash)
                download_hash $g_hash
            fi
        done
        out=$($1)
    done
}

function main
{
    print_banner
    download_initial
    echo_colour "[*] Looking for missing objects..." "y"
    recursive_download get_fsck_hashes

    cwd=$(pwd)
    cd $git_dir
    echo_colour "[*] Recovering files" "y"
    recursive_download get_reset_hashes
    cd $cwd
}

main
