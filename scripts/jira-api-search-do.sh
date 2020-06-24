#!/bin/bash

CURDIR=`pwd`
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_NAME=${CI_JOB_NAME:-"Jira-api"}
#CI_JOB_NAME=${CI_JOB_NAME:-"Notification"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}
COMHEAD=${COMHEAD:-"commheader.txt"}
ATREPORT="$CI_PROJECT_DIR/Temp/Somebase_tests/target/site/allure-maven-plugin"
JIRADSO_URL="http://task.corp.dev.mlh"
JIRADSO_USER=${JIRADSO_USER:-"pipeline-dso"}
JIRADSO_PASS=${JIRADSO_PASS:-"CtBroEE9WJ"}
JIRADSO_AUTH=$( echo -n $JIRADSO_USER:$JIRADSO_PASS|base64 )
SRCHRESKEY=${SRCHRESKEY:-"searchissue-key.txt"}
SRCHRESID=${SRCHRESID:-"searchissue-id.txt"}
SRCHRESFILE=${SRCHRESFILE:-"searchissue.json"}
ISSTATUSFILE=${ISSTATUSFILE:-"isstatus.txt"}
TESTSRESULT=${TESTSRESULT:-"numtests.txt"}
STATUSARR=([1]="open" [3]="inprogress" [10100]="todo" [10714]="testing" [10002]="done")

source ./scripts/common_func.sh
print_usage () {
	    echoout "E;" "Usage: 
		  $PROG changestatus {MLH-XXXX} - change status from INPROGRESS to TESTING
		  $PROG updatecustomcr {CR VALUE} - update CR field to CR VALUE
		  $PROG postcomment  {COMMENT TEXT} - post comment (quotes inside allowed)
		  $PROG updateatcomment {MLH-XXXX} - post autotest results comment (fail/success)
		  $PROG updateresulttable {DEPLOY RESULT FILE NAME} - update result table with that data
		    deploy result file template: somebase.fbddir-inventory_hostname-branch-text result"
}


changestatus() {
echoout "I;" "changestatus(): start"

## no need, done before start case with load_issuekey()
##ISSUEKEY=$1
if [[ "$#" -lt "1" ]]; then
    echoout "E;" "changestatus(): Too few arguments. {desiredstatus} required, ex. inprogress,testing"
    print_usage
    exit 0
fi    
DESIREDSTATUS="$1"
## ID for TESTING http://task.corp.dev.mlh/rest/api/2/issue/PR268-110/transitions
## transitions: [id: "" -> use it when transtion, to get status to:{ id:""
##TRANSSTATUS=41
## PREVSTATUS1,2 - to inprogress may trans from open, also from todo
## forced to set same 1,2 in testing/done because if must compare both
case "$DESIREDSTATUS" in
    "inprogress" )
        WILLSTATUS=3
        TRANSSTATUS=21
        TRANSNAME="In progress"
        PREVSTATUS1=1
        PREVSTATUS2=10100
            
;;
    "testing" )
        WILLSTATUS=10714
        TRANSSTATUS=41
        PREVSTATUS1=3
        PREVSTATUS2=3
        TRANSNAME="Testing"
;;        
    "done" )
        WILLSTATUS=10002
        TRANSSTATUS=199 # currently no transstatus to 'done' in api
        PREVSTATUS1=10714
        PREVSTATUS2=10714
        TRANSNAME="Testing"
        
;;
    * )
        echoout "I;" "changestatus(): Do not know desired status $DESIREDSTATUS, nothing to do"
        exit 0
esac
./scripts/gen_json_from_readme.sh catallstderr $COMMIT $COMMAND
ISSTATUS=$( grep -oP  "(?<=issue status )[0-9]+(?=: )" pipeline-stderr.txt | tail -1 )
#"
echoout "I;" "changestatus(): got (current/last) status \"$ISSTATUS\" from previous stages stderr log, written by check_issue_json()"
if [[ -z $ISSTATUS ]]; then
    echoout "I;" "changestatus(): not got (current/last) status from grep log,  cannot continue"
    exit 0
elif [[ $ISSTATUS -ne $PREVSTATUS1 && $ISSTATUS -ne $PREVSTATUS2  ]]; then
    echoout "I;" "changestatus(): called with \"$DESIREDSTATUS\", but check_issue() detect status \"${STATUSARR[$ISSTATUS]}\", which is unsuitable to transition"
    exit 0
elif [[ $ISSTATUS -eq $WILLSTATUS ]]; then
    echoout "I;" "changestatus(): called to set \"$DESIREDSTATUS\", but check_issue() detect status \"${STATUSARR[$ISSTATUS]}\" already"
    exit 0
fi
echoout "I;" "changestatus(): try status transitiion to \"$TRANSNAME\""        
DATAVAR=$( jq -c -n --arg T "$TRANSSTATUS" '{transition:{"id": $T}}' )
curl_call "POST"  "basic" "noresp" "data" "$JIRADSO_AUTH" "$DATAVAR" "$JIRADSO_URL/rest/api/2/issue/$ISSUEKEY/transitions"
if [[ "$CURLCODE" -eq "204" ]]; then
    echoout "I;" "changestatus(): SUCCESS api call status transition for $ISSUEKEY to \"$TRANSNAME\""
else
    echoout "E201;" "changestatus(): api call status transition NOT SUCCESS for $ISSUEKEY to \"$TRANSNAME\", HTTP code $CURLCODE"
fi
}

updatecustomcr() {

if [[ "$#" -lt "1" ]]; then
    echoout "E;" "updatecustomcr(): Too few arguments. {CR field} value required"
    print_usage
    exit 0
fi    
## no need, done in case
##ISSUEKEY=$1
#see arg in case
CUSTOMVAL=$1
echoout "I;" "updatecustomcr(): update custom field 11005 (CR) to $CUSTOMVAL"
DATAVAR=$( jq -nc --arg customfield_11005 "$CUSTOMVAL" '{fields:{$customfield_11005}}' )
echoout "I;" "updatecustomcr(): update json ^$DATAVAR^"
curl_call "PUT"  "basic" "noresp" "data" "$JIRADSO_AUTH" "$DATAVAR" "$JIRADSO_URL/rest/api/2/issue/$ISSUEKEY"
if [[ "$CURLCODE" -eq "204" ]]; then
    echoout "I;" "updatecustomcr(): SUCCESS api call update custom field CR for $ISSUEKEY"
else
    echoout "E202;" "updatecustomcr(): NOT SUCCESS api call update custom field CR for $ISSUEKEY, HTTP code $CURLCODE"
fi
}

post_comment() {
echoout "I;" "post_comment(): start"
if [[ "$#" -lt "1" ]]; then
    echoout "E;" "post_comment(): Too few arguments. comment text required"
    exit 0
fi    
## no need, done in case
##ISSUEKEY=$1
COMMENT="$1"
## in multiline vars cut acts on all lines, output also multiline - replace newline
#COMMENT=$( echo "$COMMENT" | tr "\n" " " )
ANNOT=$( echo "$COMMENT" | tr "\n" " " | cut -d" " -f 1-3 )
DATAVAR=$( jq -nc --arg body "$COMMENT" '{$body}' )
echoout "I;" "post_comment(): comment json ^$DATAVAR^"
echoout "I;" "post_comment(): to issue $ISSUEKEY add comment $ANNOT......"   
curl_call "POST"  "basic" "resp" "data" "$JIRADSO_AUTH" "$DATAVAR" "$JIRADSO_URL/rest/api/2/issue/$ISSUEKEY/comment"
if [[ "$CURLCODE" -eq "201" ]]; then
       echoout "I;" "post_comment(): SUCCESS Post to issue number $ISSUEKEY"
	   COMMENTID=$(echo $CURLBODY | jq -r '.id')
	   echoout "I;" "post_comment(): jq got comment id $COMMENTID; put string in log for grep comment url later"
	   COMMENTURL="$JIRADSO_URL/browse/$ISSUEKEY?focusedCommentId=$COMMENTID&page=com.atlassian.jira.plugin.system.issuetabpanels%3Acomment-tabpanel#comment-$COMMENTID"
	   echoout "post_comment(): $COMMIT COMMENTURL;" " $ANNOT $COMMENTURL "
    else
       echoout "E203;" "post_comment(): NOT SUCCESS Post comment to issue  $ISSUEKEY, HTTP code $CURLCODE"
    fi
}

updateresulttable() {
echoout "I;" "updateresulttable(): start"
if [[ "$#" -lt "2" && -z "$2" ]]; then
    echoout "E;" "updateresulttable(): Too few arguments. Required: 1. issue id; 2. File name with deploy result"
    print_usage
    exit 0
fi    
DEPLOYRESFILE=$2
[[ ! -f $DEPLOYRESFILE ]] && echoout "E204;" "updateresulttable(): Error getting deploy result: File not exist $DEPLOYRESFILE" && exit 0
PURL="$CI_PIPELINE_URL"
## unixtime in MSK timezone with microseconds
PDATE=`date +%s`000
while read FULLDEPRES; do
    OLDIFS="$IFS"
    IFS=-; ARR=($FULLDEPRES)
    HOSTBASE="${ARR[1]}${ARR[0]}"
    RESULT="branch ${ARR[2]}-${ARR[3]}"
## use --argjson for numeric argunemts: stackowerflow # 41772776
    JSON=$( jq -nc --arg base "$HOSTBASE" --arg result  "$RESULT" --arg url  "$PURL" --argjson pdate "$PDATE" '{"rows":[ { $base, $result, $url, $pdate } ] }' )
    echoout "I;" "updateresulttable(): for update table in issue id $ISSUEID generated json: $JSON"
    ## 11170 - grid id for needed table, grid list can be obtained : GET /rest/idalko-igrid/1.0/grid/list
    curl_call "POST"  "basic" "resp" "data" "$JIRADSO_AUTH" "$JSON" "$JIRADSO_URL/rest/idalko-igrid/1.0/grid/11170/issue/$ISSUEID/"
    ## return some number '[num]httpcode', like '[35]200', get http code
        if [[ "$CURLCODE" -eq "200" ]]; then
            echoout "I;" "updateresulttable(): SUCCESS api call update result table for issue number id $ISSUEID"
        else
            echoout "E205;" "updateresulttable(): NOT SUCCESS api call update result tables for issue number id $ISSUEID, HTTP code $CURLCODE"
        fi
    IFS="$OLDIFS"
done < $DEPLOYRESFILE
}

updateatcomment() {

if [[ "$#" -lt "2" ]]; then
    echoout "E;" "updateatcomment(): Too few arguments. 'numfailed numall' required"
    print_usage
    exit 0
fi    

NUMFAILED="$1"
NUMALL="$2"

echoout "I;" "updateatcomment(): tests result readed $NUMFAILED / $NUMALL"
echoout "I;" "updateatcomment(): add comment to issue $ISSUEKEY about tests: FAILED Tests $NUMFAILED, ALL Tests: $NUMALL "
if [[ $NUMFAILED -gt 0 ]]; then
   FAILTESTNAME=$( cat failedtests.txt )
   FAILTESTNAME=${FAILTESTNAME//$'\n'/}
   echoout "E;" "updateatcomment(): found failed tests: $NUMFAILED"   
   post_comment "Упавших тестов: $NUMFAILED,  Общее количество: $NUMALL, Pipeline $CI_PIPELINE_ID, ссылка на job $CI_JOB_URL, имена: $FAILTESTNAME "
else 
   echoout "I;" "updateatcomment(): post comment about successful tests: $NUMALL"
   post_comment "Тесты успешны: $NUMALL (Все), Pipeline $CI_PIPELINE_ID "
fi    

}


###----------------------------- main -------------------------------


if [[ "$#" -lt "1" ]]; then
    echoout "E290;" "main(): Too few arguments. {command} required, see usage"
    print_usage
    exit 0
fi    

COMMAND=$1
# now it is own function parameter in $2
#COMMIT=$2
echoout "I;" "Start $0 $*"
 
if check_vendor; then
    echoout "I;" "main(): check_vendor() result: vendor: ^$VENDOR^ good, continue"
else
    echoout "E;" "main(): check_vendor() result: vendor: ^$VENDOR^ bad, exit"
    exit 0
fi    

load_issuekey
 
case "$COMMAND" in
    "changestatus" )
        changestatus "$2"
;;
    "updatecustomcr" )
        # arg : new cr field value
        updatecustomcr "$2"
;;
    "postcomment" )
        # arg : comment
        post_comment  "$2"
;;
    "updateresulttable" )
        # arg : issue id number, deploy res file.txt 
        updateresulttable $ISSUEID "$2"
;;
    "updateatcomment" )
        updateatcomment "$2" "$3" 
;;
    * )
        echoout "E291;" "main(): command not suitable : $COMMAND"
        print_usage
esac


 
