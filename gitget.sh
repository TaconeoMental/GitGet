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
        o) OUT_DIR="$OPTARG" ;;
        r) REPO_URL="$OPTARG" ;;
        \:)
            print_banner
            echo_colour "Option '-$OPTARG' needs an argument" "r"
            help_msg
            ;;
    esac >&2
done

if [ -z "$OUT_DIR" ] || [ -z "$REPO_URL" ]
then
    print_banner
    help_msg
fi

if [[ ! "$REPO_URL" =~ /.git/$ ]];
then
    print_banner
    echo_colour "[-] /.git/ missing in URL" "r"
    exit 1
fi

# Helpers
function grep_hashes()
{
    local out=$(grep -av "\.git" - | grep -Eoa "[a-f0-9]{40}" | sort -u)
    echo $out
}

# Globals
GIT_OUT_DIR="$OUT_DIR/.git/"
SWAP_FILE="$OUT_DIR/.gitget.swp"
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
        download_file "$file"
    done
}

function download_file()
{
    local file_path="$GIT_OUT_DIR$1"

    # If the file has already been checked before, skip it
    if grep -q $1 $SWAP_FILE;
    then
        return
    fi

    # Download the file if it hasn't been done already
    if [ ! -f "$file_path" ];
    then
        # We verify the HTTP status code and the content-type header
        local headers=$(curl -skI -w "%{http_code}" "$REPO_URL$1")
        local status_code="${headers:${#headers}-3}"
        if grep -qE "^content-type:.*html" <<< "$headers" || [ $status_code != 200 ];
        then
            # File doesn't exist or can't be accessed
            echo_colour "[-] $1" "r"
            echo $1 >> $SWAP_FILE
            return
        fi

        # Everything seems ok. We download the file
        curl -ks "$REPO_URL$1" --create-dirs -o "$file_path"
        echo_colour "[+] Downloaded $1" "g"
    fi

    # We look for hashes inside the file and try downloading them
    for h in $(cat $file_path | grep_hashes | sort -u | tr '\n' ' ')
    do
        download_hash $h
    done
}

function download_hash()
{
    local g_hash path
    g_hash="$1"
    path="/objects/${g_hash:0:2}/${g_hash:2}"
    download_file $path
}

function get_fsck_hashes()
{
    local fsck_out=$(git --git-dir=$GIT_OUT_DIR fsck |& grep -E "(blob|tree|commit)" | grep_hashes)
    echo $fsck_out
}

function get_reset_hashes()
{
    local reset_out=$(cd $OUT_DIR; git reset --hard |& grep_hashes)
    echo $reset_out
}

function function_download()
{
    # $1: hash generator function
    local out=$($1)
    while true;
    do
        # Stop if the function doesn't generate any more hashes
        [ -z "$out" ] && break
        for g_hash in $out
        do
            download_hash $g_hash
        done

        # Stop if none of the hashes generated could be downloaded
        out_f=$($1)
        [ "$out" == "$out_f" ] && break
        out="$out_f"
    done
}

function main
{
    print_banner

    # We see if directory listing is enabled
    status_code=$(curl -kI --write-out '%{http_code}' --output /dev/null --silent "$REPO_URL")
    if [ "$status_code" = 200 ];
    then
        # If it is, we just download recursively
        echo_colour "[+] Directory listing enabled! Downloading all files" "g"
        wget "$REPO_URL" \
            --recursive \
            --no-check-certificate \
            --execute robots=off \
            --no-parent \
            --quiet \
            --show-progress \
            --no-host-directories \
            --reject "index.html" \
            --reject-regex "\?.=.;.=." \
            --directory-prefix $OUT_DIR

        echo_colour "[*] Recovering files"
        (cd $OUT_DIR; git reset --hard)

        echo_colour "[+] All done!" "g"
        return
    fi

    mkdir -p $OUT_DIR
    if [ -f $SWAP_FILE ];
    then
        echo_colour "[*] Swap file found, resuming downloads"
    else
        echo_colour "[*] Creating swap file"
        echo -e "# GitGet swap file\n#$REPO_URL" > $SWAP_FILE
    fi

    download_initial
    echo_colour "[*] Looking for missing objects"
    function_download get_fsck_hashes

    echo_colour "[*] Recovering files"
    function_download get_reset_hashes

    echo_colour "[*] Deleting swap file"
    rm $SWAP_FILE

    echo_colour "[+] All done!" "g"
}

main
