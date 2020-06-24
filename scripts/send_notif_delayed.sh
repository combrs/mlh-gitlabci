#!/bin/bash

CURDIR=$(pwd)
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_NAME=${CI_JOB_NAME:-"Notification"}

source ./scripts/common_func.sh

check_unsent() {
    echoout "I;" "check_unsent(): start"
    UNSENT_ARR=($(compgen -G "*.json.unsent.*"))
    if [[ "${#UNSENT_ARR[@]}" -gt 0 ]]; then
        echoout "E627;" "check_unsent(): ${#UNSENT_ARR[@]} unsent files found"
        return "${#UNSENT_ARR[@]}"
    else
        echoout "I;" "send_unsent(): no unsent files found"
    fi

}

send_unsent() {
    run_command "mkdir -vp $CI_PROJECT_DIR/sent"
    for file in ${UNSENT_ARR[@]}; do
        echoout "I;" "send_unsent(): found unsent file $file, resend it via smtp"
        case "${file%%.*}" in
        mail|mail-jirawarn)
            gen_json_rfc822 "$file"
            send_curl_smtp "$file"
            ;;
        robot-mail)
            gen_json_rfc822 "$file"
            send_curl_smtp "$file"
            [[ $? -eq 0 ]] && ./scripts/jira-api-search-do.sh changestatus "testing"
            ;;
        jira)
            run_command "mv -vf $file ${file%%.*}.json"
            ./scripts/send_notif.sh sendjiraglhcomment
            ;;
        *)
            echoout "E;" "send_unsent(): unsent file is unknown: $file"
            ;;
        esac
    done
}

gen_json_rfc822() {
    echoout "I;" "gen_json_rfc822(): start"
    ARG1="$1"
    ATTS=()
    from="dso-prf-system-ads@dev.mlh"
    to=$(jq -r '.recipient| join(",")' "$ARG1")
    #'""
    subject=$(jq -r '.subject' "$ARG1")
    body=$(jq -r '.body' "$ARG1" | base64 -d | tr -d '\r')
    ATTNUM=$(jq -r '.attachments| length' "$ARG1")
    echoout "I;" "gen_json_rfc822(): in $ARG1 found $ATTNUM attachments"
    for ((attn = 0; attn < $ATTNUM; attn++)); do
        FORMAT=$(jq -r ".attachments[$attn].format" "$ARG1")
        FILEN=$(jq -r ".attachments[$attn].name" "$ARG1")
        if [[ "$FORMAT" == "base64" ]]; then
            echoout "I;" "gen_json_rfc822(): save attachment $FILEN, format is $FORMAT, add name to args"
            jq -r ".attachments[$attn].body" "$ARG1" | base64 -d >$FILEN
            ATTS+=("-a" "$FILEN")
        else
            echoout "I;" "gen_json_rfc822(): for ^$FILEN^ format in ^$ARG1^ is not base64, format: ^$FORMAT^, skip save file"
        fi
    done

    echoout "I;" "gen_json_rfc822(): got attach args ${ATTS[*]}"

    SENTMAIL="${CI_PROJECT_DIR}/sent/${ARG1}.rfc822"
    #mail -v -S smtp "smtp://10.203.92.180" -S sendwait -S record $SENTMAIL -s "$subject" -r "$from" "${attargs[@]}" "$to" <<< "$body"
    echoout "I;" "gen_json_rfc822(): save mail file to ${ARG1}.rfc822"
    #echoout "I;" "gen_json_rfc822(): mail ... -S record=$SENTMAIL -s $subject -r $from ${ATTS[*]} $to"
    if [[ -n "$subject" && -n "$to" && -n "$body" ]]; then
        mail -S sendmail=/bin/true -S record="$SENTMAIL" -s "$subject" -r "$from" "${ATTS[@]}" "$to" <<<"$body"
    else
        echoout "I;" "gen_json_rfc822(): lack of some jq extracted args: subj or to or body"
    fi
}

send_curl_smtp() {
    echoout "I;" "send_curl_smtp(): start"
    ARG2="$1"
    to=$(jq -r '.recipient| join(" ")' "$ARG2")
    #'""
    mailrcpt=""
    for mailto in $to; do
        mailrcpt=${mailrcpt}" --mail-rcpt $mailto"
    done
    mailfrom="--mail-from $from"

    filetosend="$CI_PROJECT_DIR/sent/$ARG2.rfc822"
    #for filetosend in $CI_PROJECT_DIR/sent/; do
    CURLOUT=$(curl -v -sS --stderr curl.stderr.${ARG2%%.*} smtp://10.203.92.180 $mailfrom $mailrcpt -T $filetosend)
    EXCODE=$?

    #echo "ffff curl.stderr.${ARG2%%.*}" > curl.stderr.${ARG2%%.*}
    #EXCODE=2

    if [[ $EXCODE -eq 0 ]]; then
        echoout "I;" "send_curl_smtp(): success curl send"
        print_multiline "I;" "$(cat curl.stderr.${ARG2%%.*})"
        sentfile="${ARG2%%.*}.json.sent"
        run_command "mv -vf $ARG2 $sentfile"
    else
        CURLSTDERR=$(cat "curl.stderr.${ARG2%%.*}")
        echoout "E;" "send_curl_smtp(): error exit, code $EXCODE, stderr:  ^$CURLSTDERR^"
        unsentfile="${ARG2%%.*}.unsent.json.smtp"
        run_command "mv -vf $ARG2 $unsentfile"
    fi
    return $EXCODE
    #done
}

### -------------### main() ###---------------
echoout "I;" "main(): START"
check_unsent
UNSENT=$?
if [[ $UNSENT -gt 0 ]]; then
    send_unsent
    echoout "I;" "main(): Recheck that unsent files sended ant no left"
    check_unsent
    UNSENT2=$?
    if [[ $UNSENT2 -gt 0 ]]; then
        echoout "E628;" "main(): After second try unsent files still here. Fail with error."
    else
        echoout "E629;" "main(): After second check_unsent() no unsent files left, exit good"
    fi
else
    ./scripts/send_notif.sh sendjiraglhcomment 
fi
