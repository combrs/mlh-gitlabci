echoout() { printf "%s $CI_JOB_NAME[$CI_JOB_ID]; $0 %s\n" "$1" "$2" | tee -a "$CI_PROJECT_DIR"/"$CI_JOB_NAME".stderr; }

print_multiline() {
    PREF=$1
    STR=$2
    while IFS= read -r line; do
        echoout "$PREF" "$line"
    done < <(printf '%s\n' "$STR")
}

run_command() {
    COMM="$1"
    CMDOUT=$($COMM 2>&1)
    CMDERR=$?
    [ $CMDERR -gt 0 ] && PREFIX="E;" || PREFIX="I;"
    print_multiline "$PREFIX" "$CMDOUT"
}

get_mails() {
    MAILS="$1"
    #arg "smtp" if need to 'mail comma separated'    
    #arg "mailto" if need to --mail-rcpt    
    TYPE="$2"
    MAILLISTS=""
    if [[ "$TYPE" == "smtp" ]]; then
        MAILLISTS=$( echo $MAILS| tr ",\"" "," )
    elif [[ "$TYPE" == "mailto" ]]; then    
        MAILLISTSP=$( grep 'To:' $MAILS | cut -d: -f 2 | tr ",\"" " " )
        for MAILTO in $MAILLISTSP; do
            MAILLISTS=${MAILLISTS}" --mail-rcpt $MAILTO"
        done
    else        
        MAILLISTS="[]"
        MAILLISTSP=$( echo $MAILS| tr ",\"" " " )
        for MAIL in $MAILLISTSP; do
            MAILLISTS=`echo $MAILLISTS | jq ". + [ \"$MAIL\" ]"`
        done
    fi
    # sub output, required
    echo $MAILLISTS
}

get_job_info() {
MODE="$1"
    echoout "I;" "get_job_info(): start, arg $MODE"
    echoout "I;" "get_job_info(): try curl to get list of $MODE $GITLABURL/projects/190/pipelines/$CI_PIPELINE_ID/jobs?scope[]=$MODE"
    curl_call "GET"  "token" "resp" "nodata" "$CI_PUSH_TOKEN" "" "$GITLABURL/projects/190/pipelines/$CI_PIPELINE_ID/jobs?scope[]=$MODE"
 	if [[ "$CURLCODE" -ne "200" ]]; then
     	echoout "E700;" "get_job_info(): Gitlab API call to get job $MODE status returned error code $CURLCODE"
    	exit 1
 	fi
#     echoout "I;" "get_job_info(): Got $MODE stage name $STAGE_NAME" 
    if [[ "$MODE" == "failed" ]]; then
 	    STAGE_NAME=$( echo "$CURLBODY" | jq -r '.[-1].name' )
        JOB=$( echo "$CURLBODY" | jq -r '.[-1].id' )
 	    REF=$( echo "$CURLBODY" | jq -r '.[-1].ref' )
        echoout "I;" "get_job_info(): failed data : name $STAGE_NAME, job $JOB, ref $REF"  
 	    FAILED_JOB_URL=$( echo "$CURLBODY" | jq -r '.[-1].web_url' )
    elif [[ "$MODE" == "success" ]]; then      
        STAGE_NAME=$( echo "$CURLBODY" | jq -r '.[].name')
        if echo "$STAGE_NAME" | grep -q 'Error_notification' ; then
            echoout "I;" "get_job_info(): Got \"$MODE\" stages ${STAGE_NAME//$'\n'/#}"
            echoout "E;" "get_job_info(): Pipeline restarted, job 'Error_notification' already completed, return 1"
            return 1
        else
            echoout "I;" "get_job_info(): stages ${STAGE_NAME//$'\n'/#} : Pipeline not complete job 'Error_notification' yet, can contunue"
        fi
    else 
        echoout "E;" "get_job_info(): Wrong arg 'mode' (required failed/success), got ^$MODE^"
    fi            
}

check_vendor() {
echoout "I;" "check_vendor(): start, try load from $COMHEAD"
if [[ -f $COMHEAD ]]; then
    echoout "I;" "check_vendor(): found $COMHEAD, start check"
# sed {N}p - print N-th line
    VENDOR=$( sed -n 2p $COMHEAD | tr "[:upper:]" "[:lower:]" )
else
    echoout "E200;" "check_vendor(): Cannot find parsed $COMHEAD in $CURDIR and get vendor, exit"
    exit 0
fi
echoout "I;" "check_vendor(): got lowercased vendor $VENDOR"
##Case-insensitive match, see gnu.org/software/bash/manual/html_node/The-Shopt-Builtin.html
##shopt -s nocasematch
### use tr lower instead

if [[ "$VENDOR" == "inhouse" || "$VENDOR" == "mlh" ]]; then
    echoout "I;" "check_vendor(): $COMMIT Supply vendor: \"$VENDOR\", operations continue" 
    return 0
else
    echoout "I;" "check_vendor(): Not do api calls in Jira-DSO, $COMMIT Supply vendor: \"$VENDOR\", exit"
    return 1
fi
##shopt -u nocasematch 
}

load_issuekey() {
    cd $CI_PROJECT_DIR
    if [[ -f $SRCHRESKEY ]]; then
        ISSUEKEY=$(cat $SRCHRESKEY)
        if [[ $ISSUEKEY == "Notfound" ]]; then
            echoout "I;" "load_issuekey(): search do not found ticket for $COMMIT, then do not call jira api"
            exit 0
        elif [[ $ISSUEKEY == "Manyfound" ]]; then
            echoout "I;" "load_issuekey(): search found many tickets for $COMMIT, no need to work with jira, exit"
            exit 0
        else
            echoout "I;" "load_issuekey(): Loaded key $ISSUEKEY"
            if [[ -f $SRCHRESID && -f $SRCHRESFILE ]]; then
                ISSUEID=$(cat $SRCHRESID)
                echoout "I;" "load_issuekey(): Loaded issueid $ISSUEID from $SRCHRESID"
                SRCHRES=$(cat $SRCHRESFILE)
                echoout "I;" "load_issuekey(): Loaded result from $SRCHRESFILE"
            else
                echoout "I;" "load_issuekey(): Absent one of the: id file $SRCHRESID or srch res file $SRCHRESFILE"
            fi
        fi
    else
        echoout "E012;" "load_issuekey(): cannot find file $SRCHRESKEY needed to call jira api"
        exit 0
    fi
}

check_branch() {
    echoout "I;" "check_branch(): start"
    if [[ "$COMMIT" != "$BRANCH" ]]; then
        echoout "I;" "check_branch(): $COMMIT is not a branch or tag, branch is $BRANCH. continue"
    else
        echoout "I;" "check_branch(): branch or tag  = supply name : $COMMIT. Disable P_DEPLOY, P_TESTS"
        P_DEPLOY="0"
        P_DEPLOY_CHECK="0"
        P_TESTS="0"
        return 2
    fi
}

curl_call() {
    CURLCODE=""
    CURLBODY=""
    CURLSTDERR=""
    CURLSIZE=""
    echoout "I;" "curl_call(): start with args:  $1 $2 $3 $4 {token, data if any} $7 $8 $9 ${10}"
    METHOD="$1"
    AUTH="$2"
    RESP="$3"
    HAVEDATA="$4"
    TOKEN="$5"
    DATA="$6"
    URL="$7"
    ADDARGS="$8"
    PROXY="$9"
    SIZE="${10}"
    ARGS=()
    if [[ "$SIZE" == "size" ]]; then
        ARGS+=(-sS --stderr curl.stderr.$$ -w "%{http_code} %{size_download}" -o "$ADDARGS")
    elif [[ -n "$ADDARGS" && "$METHOD" != "upload" && "$METHOD" != "output" ]]; then
        ARGS+=(-sS --stderr curl.stderr.$$ -w %{http_code} "$ADDARGS")
    else
        ARGS+=(-sS --stderr curl.stderr.$$ -w %{http_code})
    fi

    if [[ "$METHOD" == "GET" || "$METHOD" == "POST" || "$METHOD" == "PUT" ]]; then
        ARGS+=(-X $METHOD)
    elif [[ "$METHOD" == "upload" ]]; then
        ARGS+=(-v -X PUT --upload-file "$ADDARGS")
    elif [[ "$METHOD" == "output" ]]; then
        ARGS+=(-X GET --output "$ADDARGS")
    else
        echoout "E;" "curl_call(): wrong 1 param. required 'GET/POST/PUT', got ^$METHOD^"
    fi
    if [[ "$AUTH" == "basic" ]]; then
        AUTHSTR1="Authorization: Basic $TOKEN"
        AUTHSTR2="Content-Type: application/json"
        AUTHSTR3="Accept: application/json"
        ARGS+=(-H "$AUTHSTR1" -H "${AUTHSTR2}" -H "${AUTHSTR3}")
    elif [[ "$AUTH" == "token" ]]; then
        AUTHSTR="PRIVATE-TOKEN:$CI_PUSH_TOKEN"
        ARGS+=(-H "$AUTHSTR")
    elif [[ "$AUTH" == "noauth" ]]; then
        echo -n ""
    else
        echoout "E;" "curl_call(): wrong 2 param. required 'basic/token/noauth', got ^$AUTH^"
    fi
    if [[ "$HAVEDATA" == "data" ]]; then
        ARGS+=(-d "$DATA")
    elif [[ "$HAVEDATA" == "datafile" ]]; then
        ARGS+=(-H "Content-Type: application/json" -d @$DATA)
    elif [[ "$HAVEDATA" == "nodata" ]]; then
        echo -n ""
    else
        echoout "E;" "curl_call(): wrong 4 param. required 'data/datafile/nodata', got ^$HAVEDATA^"
    fi
    if [[ "$PROXY" == "proxy" ]]; then
        PROXYURL=" -x $MLH_PROXY_URL:$MLH_PROXY_PORT"
        ARGS+=($PROXYURL)
    fi
    ARGS+=("$URL")
    ## curl start
    ARGST=$(echo "${ARGS[@]:0:8}")
    echoout "I;" "curl_call(): start curl $ARGST ... ${ARGS[-1]}"
    CURLBODYCODE=$(curl "${ARGS[@]}")
    EXCODE=$?
    if [[ $EXCODE -eq 0 ]]; then
        if [[ "$SIZE" == "size" ]]; then
            CURLCODE=${CURLBODYCODE:0:3}
            CURLSIZE=${CURLBODYCODE:4}
        else
            CURLCODE=$(echo $CURLBODYCODE | tail -c 4)
        fi
        if [[ "$RESP" == "resp" ]]; then
            # all but 4 bytes from end
            CURLBODY=$(echo "$CURLBODYCODE" | head -c -4)
        elif [[ "$RESP" == "noresp" ]]; then
            #echoout "I;" "curl_call(): noresp arg, not to get output from stdout"
            echo -n ""
        else
            echoout "E;" "curl_call(): wrong 3 param. required 'resp/noresp', got ^$RESP^"
        fi
        if [[ -n "$CURLBODY" && "$CURLCODE" -gt 300 && "$CURLCODE" -ne 404  ]]; then
            # E037 is unknown now, then output log string with responce "as is" in mail
            echoout "E037;" "http code: $CURLCODE. Responce: $CURLBODY"
        fi    
        if [[ "$METHOD" == "upload" ]]; then
            echoout "I;" "curl_call(): upload file, get verbose from stderr"
            CURLBODY=$(cat "curl.stderr.$$")
            rm -vf "curl.stderr.$$"
        fi
        if [[ "$METHOD" == "output" && $CURLCODE -gt 300 ]]; then
            echoout "I;" "curl_call(): unsuccessful try with --output file, delete file: $ADDARGS"
            rm -vf "$ADDARGS"
        fi
    else
        CURLSTDERR=$(cat "curl.stderr.$$")
        echoout "E;" "curl_call(): error exit, stderr:  ^$CURLSTDERR^"
        if [[ "$METHOD" == "POST" && "$AUTH" == "noauth" && "$RESP" == "noresp" && "$HAVEDATA" == "datafile"  ]]; then
            echoout "I;" "curl_call(): called from send_notif to connect to mailsend at port 9080, skip if failed"        
        else
            exit 1
        fi
        
    fi
    echoout "I;" "curl_call(): CURLCODE $CURLCODE"
}
