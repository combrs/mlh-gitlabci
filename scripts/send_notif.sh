#!/bin/bash 

CURDIR=$( pwd )
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}
CI_JOB_NAME=${CI_JOB_NAME:-"Notification"}
CI_PIPELINE_ID=${CI_PIPELINE_ID:-"77443"}
MLH_PROXY_URL=${MLH_PROXY_URL:-"10.64.40.155"}
MLH_PROXY_PORT=${MLH_PROXY_PORT:-"8080"}
JIRA_USER=${JIRA_USER:-"fbd.stbuilder"}
JIRA_PASS=${JIRA_PASS:-"UeJkjWV5P8nPhyzY"}
JIRA_URL=${JIRA_URL:-"https://jira-sup.glh.ru/rest/api/2/issue"}
GITLABURL=${GITLABURL:-"http://ci.corp.dev.mlh/api/v4/"}
JIRA_AUTH=$( echo -n $JIRA_USER:$JIRA_PASS|base64 )
COMHEAD=${COMHEAD:-"commheader.txt"}
MAILJSONFILE=${MAILJSONFILE:-"mail.json"}
MAILJIRAWARNJSONFILE=${MAILJIRAWARNJSONFILE:-"mail-jirawarn.json"}
JIRAGLHJSONFILE=${JIRAGLHJSONFILE:-"jira.json"}
ATTESTWARNJSONFILE=${ATTESTWARNJSONFILE:-"Auto_testing.json"}
DEPLOYCHECKERRFILE=${DEPLOYCHECKERRFILE:-"check-notok.txt"}
CI_JOB_NAME=${CI_JOB_NAME:-"Notification"}
MAIL_LIST_REPORT=${MAIL_LIST_REPORT:-"mlykov@mlh.ru, mlh214277@dev.mlh"}
MAIL_SERVER=${MAIL_SERVER:-"http://10.203.92.186:9080"}
SMTP_SERVER=${SMTP_SERVER:-"smtp://10.203.92.180"}
SMTP_FROM="dso-prf-system-ads@dev.mlh"

source ./scripts/common_func.sh

print_usage() {
    PROG=`basename $0`  
        echo  "Usage:
                $PROG sendjiraglhcomment - http post jira.json to Jira GLH 
                $PROG sendmailjsonfile [robot] - send mail.json via mailsend http sender [robot - use changestatus() after success)  
                $PROG sendmailjirawarnfile  - send mail-jirawarn.json to maillist_report with warning in JIRA DSO
                $PROG sendattestwarnfile  - send Auto_testing.json with list of failed tests
                $PROG sendnotiferrs - - send mail.json via mailsend http sender with errors caused when exec previous commands" 
}

send_jira_glh_comment() {
if [[ "$P_PROD_MAIL" != "true" ]]; then
    echoout "I;" "send_jira_glh_comment(): P_PROD_MAIL ^$P_PROD_MAIL^ - not post to Jira GLH"
    return
fi    
echoout "I;" "send_jira_glh_comment(): try to find $JIRAGLHJSONFILE"
if [ -f $JIRAGLHJSONFILE ]; then
	echoout "I;" "send_jira_glh_comment(): Found $JIRAGLHJSONFILE, try to send comment to Jira GLH  $JIRA_URL/$COMMIT/ via proxy $MLH_PROXY_URL:$MLH_PROXY_PORT"
	if [[ "$NO_DELIVERY" != "true" ]]; then
        curl_call "POST" "basic" "noresp" "datafile" "$JIRA_AUTH" "$JIRAGLHJSONFILE" "$JIRA_URL/$COMMIT/comment" "" "proxy"
    else
       echoout "I;" "send_jira_glh_comment(): NO_DELIVERY=\"$NO_DELIVERY\" : enabled, do not post about 'not checked deploy result' in checkatresult, exit"
       exit 0 
    fi # if no_delivery
    if [[ "$CURLCODE" -eq "201" ]]; then
    	if grep "Delivery checks failed" $JIRAGLHJSONFILE; then
       		echoout "I;" "send_jira_glh_comment(): Jira GLH comment about Failed delivery sent successfully, code $CURLCODE"
       	else	
       		echoout "I113;" "send_jira_glh_comment(): Jira GLH comment about successful delivery sent, code $CURLCODE."
        fi 
        run_command "mv -vf $JIRAGLHJSONFILE  $JIRAGLHJSONFILE.sent.$$"
    elif  [[ "$CURLCODE" -eq "404" ]]; then
       echoout "E600;" "send_jira_glh_comment(): Did not find issue when posting comment to Jira GLH, code $CURLCODE. responce $CURLBODY"
    elif  [[ "$CURLCODE" -eq "500" ]]; then
    	echoout "E601;" "send_jira_glh_comment(): Server error when posting comment to Jira GLH, code $CURLCODE. responce $CURLBODY"
    elif  [[ "$CURLCODE" -eq "403" ]]; then    	
        echoout "E602;" "send_jira_glh_comment(): Access denied when posting comment to Jira GLH, code $CURLCODE. responce $CURLBODY"
    elif  [[ "$CURLCODE" -eq "000" ]]; then    	
        echoout "E613;" "send_jira_glh_comment(): Cannot connect to $JIRA_URL, http error '000', see stderr"
    else 
        echoout "E603;" "send_jira_glh_comment(): Other error when posting comment to Jira GLH (not 403, 404, 500), code $CURLCODE. responce $CURLBODY"
    fi
    echoout "I;" "send_jira_glh_comment(): if mail not sent, try to rename file to unsent-no place in if, ignore 'No such file' below"
    run_command "mv -vf $JIRAGLHJSONFILE  $JIRAGLHJSONFILE.unsent.$$"
else
    echoout "E632;" "send_jira_glh_comment(): Cannot find $JIRAGLHJSONFILE for posting comment to Jira GLH"
fi
}

save_result_send() {
   if [[ $CI_JOB_NAME == "Notification" ]]; then
	    echoout "I112;" "save_result_send(): Notification: Mail with readme sent Successfully, code $CURLCODE. change issue status in JIRA-DSO"
        run_command "mv -vf $MAILJSONFILE  $MAILJSONFILE.sent.$$"    
        ## ARGMAIL comes from caller send_mail_json_file()
        if [[ "$ARGMAIL" == "robot" ]]; then       
            ./scripts/jira-api-search-do.sh changestatus "testing"
        else
            echoout "I;" "save_result_send(): No arg robot, send for human, do not changestatus()"
        fi      
	else
        echoout "I;" "save_result_send(): job $CI_JOB_NAME, Mail with error descriptions sent Successfully, code $CURLCODE"
	fi  
}     

send_curl_smtp() {
    echoout "I;" "send_curl_smtp(): start with ^$1^"
    filejson="$1"
    #to=$(jq -r '.recipient| join(" ")' "$filejson")
    ##'""
    #echoout "I;" "send_curl_smtp(): got recipients from $filejson: ^$to^"
    filetosend="$filejson.rfc822"
    if [ -f "$filetosend" ]; then
        echoout "I;" "send_curl_smtp(): Found file $filetosend"
    else    
        echoout "E631;" "send_curl_smtp(): cannot find $filetosend"
        return 1
    fi    
    #mailrcpt=""
    #for mailto in $to; do
    #    mailrcpt=${mailrcpt}" --mail-rcpt $mailto"
    #done
    mailfrom="--mail-from $SMTP_FROM"
    RECIPSMTP=$(get_mails "$filetosend" "mailto")
    echoout "I;" "send_curl_smtp(): call curl: curl -v -sS --stderr curl.stderr.${filetosend%%.*} $SMTP_SERVER $mailfrom $RECIPSMTP -T $filetosend"
    CURLOUT=$(curl -v -sS --stderr curl.stderr.${filetosend%%.*} $SMTP_SERVER $mailfrom $RECIPSMTP -T $filetosend)
    EXCODE=$?
    #echo "ffff curl.stderr.${filetosend%%.*}" > curl.stderr.${filetosend%%.*}
    #EXCODE=2
    if [[ $EXCODE -eq 0 ]]; then
        echoout "I;" "send_curl_smtp(): success curl send"
        print_multiline "I;" "$(cat curl.stderr.${filetosend%%.*})"
        run_command "mv -vf $filetosend ${filetosend}.sent.$$"
    else
        CURLSTDERR=$(cat "curl.stderr.${filetosend%%.*}")
        echoout "E628;" "send_curl_smtp(): error exit, code $EXCODE, stderr:  ^$CURLSTDERR^"
        run_command "mv -vf $filetosend ${filetosend}.unsent.$$"
    fi
    echoout "I;" "send_curl_smtp(): return code $EXCODE"
    return $EXCODE
    #done
}

send_mail_json_file() {

ARGMAIL=$1
if [[ $ARGMAIL == "robot" ]]; then 
    MAILJSONFILE="robot-"${MAILJSONFILE}
fi    
echoout "I;" "send_mail_json_file():  try to find $MAILJSONFILE"
if [[ -f $MAILJSONFILE ]]; then
    echoout "I;" "send_mail_json_file(): Found $MAILJSONFILE, try to send mail with readme/error via  via $MAIL_SERVER"
    curl_call "POST"  "noauth" "noresp" "datafile" "" "$MAILJSONFILE" "$MAIL_SERVER"
    if [[ "$CURLCODE" -eq "200" ]]; then
        save_result_send $MAILJSONFILE
    else

        send_curl_smtp ${MAILJSONFILE%.json}
        if [[ $? -eq 0 ]]; then
          save_result_send $MAILJSONFILE
        else
            echoout "E624;" "send_mail_json_file(): Error when sending mail $MAILJSONFILE with readme or errors, code $CURLCODE"
            run_command "mv -vf $MAILJSONFILE  $MAILJSONFILE.unsent.$$"
        fi    
    fi
    run_command "mv -vf $DEPLOYCHECKERRFILE  $DEPLOYCHECKERRFILE.used.$$"
else
    echoout "E620;" "send_mail_json_file(): Cannot find $MAILJSONFILE for sending mail with readme for robot or human"
fi
}

send_mail_jirawarn_file() {
echoout "I;" "send_mail_jirawarn_file(): start. try to find $MAILJIRAWARNJSONFILE"
## if file size > 0
if [[ -s $MAILJIRAWARNJSONFILE ]]; then
	echoout "I;" "send_mail_jirawarn_file(): Found $MAILJIRAWARNJSONFILE, try to send mail with Jira DSO errors via $MAIL_SERVER"
    curl_call "POST"  "noauth" "noresp" "datafile" "" "$MAILJIRAWARNJSONFILE" "$MAIL_SERVER"
    if [[ "$CURLCODE" -eq "200" ]]; then
		echoout "I;" "send_mail_jirawarn_file(): Mail with jira DSO warning sent Successfully, code $CURLCODE"
        run_command "mv -vf $MAILJIRAWARNJSONFILE $MAILJIRAWARNJSONFILE.sent.$$"
    else
		echoout "E625;" "send_mail_jirawarn_file(): Error when sending mail with jira DSO warning, code $CURLCODE"
        send_curl_smtp ${MAILJIRAWARNJSONFILE%.json}
    fi #if curlcode
else
    if check_vendor; then
        if [ -f $MAILJIRAWARNJSONFILE ]; then
            echoout "I;" "send_mail_jirawarn_file(): $MAILJIRAWARNJSONFILE is empty, but vendor ^$VENDOR^. No errors in Jira"
        else
            echoout "E621;" "send_mail_jirawarn_file(): Not found $MAILJIRAWARNJSONFILE, but vendor ^$VENDOR^. Some error when creating it"
        fi  # if file exist
    else
        echoout "I;" "send_mail_jirawarn_file(): vendor ^$VENDOR^ , not send any warn file"
    fi  # if check_vendor  
fi  # if file exist and size > 0
}

send_attest_warn_file() {
echoout "I;" "send_attest_warn_file(): start. try to find $ATTESTWARNJSONFILE"
if [ -f $ATTESTWARNJSONFILE ]; then
        echoout "I;" "send_attest_warn_file(): Found $ATTESTWARNJSONFILE, try to send letter with failed tests"
        curl_call "POST"  "noauth" "noresp" "datafile" "" "$ATTESTWARNJSONFILE" "$MAIL_SERVER"
            if [[ "$CURLCODE" -eq "200" ]]; then
                echoout "I;" "send_attest_warn_file(): Mail with failed autotest results sent Successfully, code $CURLCODE"
            else
                send_curl_smtp ${ATTESTWARNJSONFILE%.json}
                [ $? -eq 0 ] || echoout "E623;" "send_attest_warn_file(): Error when sending mail with failed autotest results, code $CURLCODE"
            fi
else
   get_job_info "failed"
   if [[ "$STAGE_NAME" == "Auto_testing" ]]; then
        echoout "E622;" "send_attest_warn_file(): Failed stage $STAGE_NAME, but cannot find $ATTESTWARNJSONFILE after genformailfile() to send failed autotest results"
    else
        echoout "E;" "send_attest_warn_file(): Failed stage $STAGE_NAME, no need to read $ATTESTWARNJSONFILE"
   fi #failed stage = autotesting
fi # attestfile exist
}

send_sendnotif_errs() {
echoout "I;" "send_sendnotif_errs(): start. try to cat all stderr files to $CI_JOB_NAME-stderr.txt"
if cat ./$CI_JOB_NAME*.stderr > $CI_JOB_NAME-stderr.txt; then
    if grep -E '^E62[0-9];' $CI_JOB_NAME-stderr.txt > $CI_JOB_NAME-E62.txt ; then
         echoout "E;" "send_sendnotif_errs(): Some E62* errors occured while send_notif.sh was run after gen_for_jira_warn() in job $CI_JOB_NAME, generate file with that errors"
         echoout "E;" "send_sendnotif_errs(): Currently E62* in send_mail_jirawarn_file() only"
         ./scripts/gen_json_from_readme.sh genformailerr $CI_JOB_NAME-E62.txt
         ./scripts/send_notif.sh sendmailjsonfile
    else
         echoout "I;" "send_sendnotif_errs(): No numbererrors occured after send in this stage"
    fi
else
    echoout "I;" "send_sendnotif_errs(): Not found $CI_JOB_NAME.stderr after this stage at all"
fi
    
}

if [[ "$#" -lt "1" ]]; then
    echoout "E;" "Too few arguments!"
    print_usage
    exit 0
fi

echoout "I;" "main(): Start $0 with arguments $*"
COMMAND="$1"
##COMMIT="$2"
echoout "I;" "main(): command $COMMAND arg2 $2"

echoout "I;" "main(): vars P_SEND_NOTIFICATION $P_SEND_NOTIFICATION NO_DELIVERY $NO_DELIVERY"
if [[ "$P_SEND_NOTIFICATION" != "true" || "$NO_DELIVERY" == "true" ]]; then
    echoout "I;" "main(): Do not send anything because this vars, Notification disabled. exit with success"
    exit 0    
fi   

## exclude previous errors cause infinite loop
run_command "mv -vf $CI_JOB_NAME.stderr $CI_JOB_NAME-before.$$.stderr"

case "$COMMAND" in
    "sendjiraglhcomment" )
        send_jira_glh_comment
    ;;  
    "sendmailjsonfile" )
        send_mail_json_file $2
    ;;
    "sendmailjirawarnfile" )
        send_mail_jirawarn_file
    ;;
    "sendattestwarnfile" )
        send_attest_warn_file
    ;;
    "sendnotiferrs" )
        send_sendnotif_errs
    ;;
    * )
       echoout "E;" "main(): command not suitable : $COMMAND"
    print_usage
esac
  
