#!/bin/bash

file="webmonitoring/status.json"
bot_token="YOUR_BOT_TOKEN"
chat_id="YOUR_CHAT_ID"
websites=()

function read_file {
    while IFS= read -r line; do
        check_website "$line"
    done < "$1"
}

function check_file_handler {
    if [ ! -f "$file" ]; then
        echo "{\"sites\": {}}" > "$file"
        echo "File $file created."
        return 0
    else
        echo "File $file already exists."
        return 1
    fi
}

function read_site_status {
    site=$1
    if [[ $site == https://* ]]; then
        site=${site:8}
    elif [[ $site == http://* ]]; then
        site=${site:7}
    fi
    status=$(jq -r ".sites[\"$site\"].Status" "$file" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "None"
    else
        echo "$status"
    fi
}

function write_json {
    site=$1
    status=$2
    if [[ $site == https://* ]]; then
        site=${site:8}
    elif [[ $site == http://* ]]; then
        site=${site:7}
    fi
    jq ".sites[\"$site\"] = $status" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

function send_notification {
    message=$1
    status=$2
    prev_status=$3
    status_code=$4
    datestr=$(date +"%d/%m/%Y-%H:%M:%S")
    if [[ $status != $prev_status ]]; then
        if [[ $message == https://* ]]; then
            message=${message:8}
        elif [[ $message == http://* ]]; then
            message=${message:7}
        fi
        if [[ $status == "Live" ]]; then
            last_live=$(date +"%d/%m/%Y-%H:%M:%S")
            write_json "$message" "{\"Status\": \"$status\",\"Last Live\": \"$last_live\"}"
            statuses="$status 🟩"
            prev_last_down=$(jq -r ".sites[\"$message\"].\"Last Down\"" "$file")
            if [[ $prev_last_down != "null" ]]; then
                curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d "chat_id=$chat_id&text=[$datestr] Diinfokan Web $message Status: $status, Last Live: $last_live HTTP_Status_Code: [$status_code] Last Down: $prev_last_down"
            else
                curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d "chat_id=$chat_id&text=[$datestr] Menginfokan Web $message Status: Live 🟩, Last Live: $last_live, HTTP_Status_Code: [$status_code]"
            fi
        else
            last_down=$(date +"%d/%m/%Y-%H:%M:%S")
            write_json "$message" "{\"Status\": \"$status\",\"Last Down\": \"$last_down\"}"
            status="$status ❌"
            prev_last_live=$(jq -r ".sites[\"$message\"].\"Last Live\"" "$file")
            if [[ $prev_last_live != "null" ]]; then
                curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d "chat_id=$chat_id&text=[$datestr] Diinfokan Web $message Status: $status, Last Down: $last_down HTTP_Status_Code: [$status_code] Last Live: $prev_last_live"
            else
                curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" -d "chat_id=$chat_id&text=[$datestr] Diinfokan Web $message Status: Down ❌, Last Down: $last_down, HTTP_Status_Code: [$status_code]"
            fi
        fi
    fi
}

function check_website {
    url=$1
    status_code=$(curl -s -o /dev/null -w "%{http_code}" -L "$url")
    if [ "$status_code" == "200" ]; then
        status="Live"
        prev_status=$(read_site_status "$url")
        send_notification "$url" "$status" "$prev_status" "$status_code"
    elif [ "$status_code" == "301" ]; then
        new_location=$(curl -s -o /dev/null -w "%{redirect_url}" "$url")
        echo "URL $url has been permanently moved to $new_location"
        check_website "$new_location"  # Recursive call to check the new location
    else
        status="Down"
        prev_status=$(read_site_status "$url")
        send_notification "$url" "$status" "$prev_status" "$status_code"
    fi
}

echo "Program started."
check_file_handler

while getopts "d:f:l:" opt; do
  case $opt in
    d)
      websites=("${websites[@]}" "$OPTARG")
      ;;
    f)
      read_file "$OPTARG"
      ;;
    l)
      while IFS= read -r domain; do
          websites=("${websites[@]}" "$domain")
      done < "$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
  esac
done

for k in "${websites[@]}"; do
    check_website "$k"
done
