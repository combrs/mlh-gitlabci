#!/bin/bash

CURDIR=`pwd`
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_NAME=${CI_JOB_NAME:-"Jira-api"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}
ATREPORT="$CI_PROJECT_DIR/Temp/Somebase_tests/target/site/allure-maven-plugin"
JIRADSO_URL="http://task.corp.dev.mlh"
JIRADSO_USER=${JIRADSO_USER:-"pipeline-dso"}
JIRADSO_PASS=${JIRADSO_PASS:-"CtBroEE9WJ"}
JIRADSO_AUTH=$( echo -n $JIRADSO_USER:$JIRADSO_PASS|base64 )
CONFDSO_USER=${CONFDSO_USER:-"dso-prf-system-ads"}
CONFDSO_PASS=${CONFDSO_PASS:-"Bipj0jLa"}
CONF_AUTH=$( echo -n $CONFDSO_USER:$CONFDSO_PASS|base64 )
CONF_URL="http://wiki.corp.dev.mlh/rest/api/content"
JIRACHKRESFILE=${JIRACHKRESFILE:-"jiradso.chkres"}
SRCHRESKEY=${SRCHRESKEY:-"searchissue-key.txt"}
SRCHRESID=${SRCHRESID:-"searchissue-id.txt"}
ISSTATUSFILE=${ISSTATUSFILE:-"isstatus.txt"}
SRCHRESFILE=${SRCHRESFILE:-"searchissue.json"}
COMHEAD=${COMHEAD:-"commheader.txt"}
ASSTABLEFILE=${ASSTABLEFILE:-"assigntable.txt"}

source ./scripts/common_func.sh
print_usage () {
        echoout "E;" "Usage: (required env. variable '$COMMIT' like 'MLH-XXXX')
            $PROG searchissueformlh  - check for project, module, type, status
            $PROG checkissue  - check for project, module, type, status
            $PROG checkvendor - check vendor suitable to query Jira
            $PROG loadissuekey - load results of search in Jira
            $PROG assignissue {issuekey} {jiralogin}  - assign issue {issuekey} to user {jiralogin}"
}


declare -A ASSTABLEARR
get_jirausers() {
echoout "I;" "get_jirausers(): start "
if [[ -f  "$CI_PROJECT_DIR"/$ASSTABLEFILE ]]; then
    echoout "I;" "get_jirausers(): $ASSTABLEFILE Already exist, skip curl request to jira and read jira users for assign from file"
    ASSTABLE=$( cat "$ASSTABLEFILE" )
else
    echoout "I;" "get_jirausers(): $ASSTABLEFILE not exist "
    curl_call "GET"  "basic" "resp" "nodata" "$CONF_AUTH" "" "$CONF_URL/35112881?expand=body.storage"
    if [[ "$CURLCODE" -ne "200" ]]; then
        echoout "E023;" "get_jirausers(): can NOT get jira users to assign (fail), HTTP status code $CURLCODE, exit"
        exit 0
    fi
    ASSTABLE=$( echo "$CURLBODY" | jq '.body.storage.value' | sed 's#</tr>#\'$'\n#g' | awk -F "<td" '{print $2"#"$3}' | sed -r 's#(colspan=\\"1\\">|</td>|>|</?span|</?p|&quot;|&nbsp;|class=\\"nolink\\")##g' )
    echoout "I;" "get_jirausers(): save assign table for jira users: $(echo $ASSTABLE | wc -l) to $ASSTABLEFILE"
    echo "$ASSTABLE" > $ASSTABLEFILE
fi
OLDIFS=$IFS
while read line; do
    IFS='#' read V1 V2 <<< $line
#   echo z111 "-$V1-" zz222 "$V2"
    if [ -n "$V1" ]; then
        # remove spaces from keys and values, if any,for consistency
        V1=${V1// /}
        V2=${V2// /}
        ASSTABLEARR["$V1"]="$V2"
    fi
done < <(echo "$ASSTABLE" )
IFS=$OLDIFS
#   echo "ASSTABLEARR elements: ${!ASSTABLEARR[*]}"
echoout "I;" "get_jirausers(): end filling ASSTABLEARR assoc array, ${#ASSTABLEARR[*]} elements"
}

check_jirauser() {
ARG1="$1"    
echoout "I;" "check_jirauser(): start check jira user $ARG1"
if [[ -n "$ARG1" ]]; then
    echoout "I;" "check_jirauser(): jira user for \"$AUTHOR\" : \"$JIRAUSER\""
    curl_call "GET" "basic" "resp" "nodata" "$JIRADSO_AUTH" "" "$JIRADSO_URL/rest/api/2/user?key=$ARG1"
    USERSTATUS=$( jq '.active' <<< "$CURLBODY" )
    JIRAFULLUSER=$( jq '.displayName' <<< "$CURLBODY" )
    if [[ "$USERSTATUS" == "true" ]]; then
        echoout "I;" "check_jirauser(): jira user $ARG1 active is $USERSTATUS, can assign to it"
    else
        echoout "E028;" "check_jirauser(): jira user $ARG1 active is $USERSTATUS, assign to pipeline-dso"
        echo "Автор $AUTHOR не активен (отключен) в Jira $JIRADSO_URL, задача будет назначена на логин 'pipeline-dso'" >> $JIRACHKRESFILE
        JIRADESC=${JIRADESC}$( echo -e "\r\n"; echo -n " Не была назначена на пользователя $JIRAFULLUSER потому что он не был включен (был неактивный) в Jira. На таких пользователей назначить задачу невозможно." )
        JIRAUSER="pipeline-dso"
        AUTHOR="pipeline-dso"
    fi    
else
    echoout "E027;" "check_jirauser(): jira user for \"$AUTHOR\" not found, create issue and assign to 'pipeline-dso'"
    echo "Автор $AUTHOR не найден среди 'пользователей Jira', задача будет назначена на логин 'pipeline-dso'" >> $JIRACHKRESFILE
    JIRADESC=${JIRADESC}$( echo -e "\r\n"; echo -n " Не была назначена на пользователя \"$AUTHOR\" потому что он не был найден в списке пользователей на wiki" )
    JIRAUSER="pipeline-dso"
    AUTHOR="pipeline-dso"
fi
}

create_issue() {
echoout "I;" "create_issue(): start "
if check_vendor; then
    echoout "I;" "create_issue(): check_vendor() result: vendor: ^$VENDOR^ good, continue"
else
    echoout "E;" "create_issue(): check_vendor() result: vendor: ^$VENDOR^ bad, exit"
    exit 0
fi  
SUBJ=$( sed -n 1p $COMHEAD )
AUTHOR=$( sed -n 3p $COMHEAD )
AUTHR=${AUTHOR// /}
echoout "I;" "create_issue(): load author, subj, from $COMHEAD (^ is dividers, not var parts): ^$AUTHR^, ^$SUBJ^"
get_jirausers
JIRAUSER=${ASSTABLEARR[$AUTHR]}
JIRADESC="Задача, созданная из pipeline somebase_ci для поставки MLH-$MLHNUM ($SUBJ)."
check_jirauser $JIRAUSER
DATAVAR=$( jq -c -n --arg summary "[auto] $SUBJ" \
             --arg customfield_11000 "$MLHNUM" \
             --arg description "$JIRADESC" \
             --arg name "$JIRAUSER" \
         '{ fields:  {
        $summary,
        "priority": { "id": "3" },
        "issuetype": { "id": "10410" },
        "components": [  { "id": "10905" } ],
        $customfield_11000,
        "customfield_11001": { "id": "10400", value: "Somebase Host" },
        "project": { "id": "10505" },
        $description,
        "assignee": { $name },
         }, }' )
echoout "I;" "$DATAVAR"

echoout "I;" "createissue(): call jira api /issue to create with json above"
curl_call "POST"  "basic" "resp" "data" "$JIRADSO_AUTH" "$DATAVAR" "$JIRADSO_URL/rest/api/2/issue"
echo "$CURLBODY" > curlbody-createresp-$MLHNUM.json
if [[ "$CURLCODE" -ne "201" ]]; then
     echoout "E024;" "createissue(): NOT created issue in Jira (fail), HTTP status code $CURLCODE, exit"
     exit 0
fi
ISSUEKEY=$( echo "$CURLBODY" | jq -r .key )
ISSUEID=$( echo "$CURLBODY" | jq -r .id )
echoout "I;" "createissue(): got responce with issuekey $ISSUEKEY and ISSUEID $ISSUEID"
}


assign_issue() {
if [[ "$#" -lt "2" ]]; then
    echoout "E;" "assign_issue(): Too few arguments.  {issuekey} and {jiralogin} required, ex. PR268-MMM mlh214NNN"
    print_usage
    exit 0
fi  

ISSUEKEY="$1"
JIRAUSER="$2"
echoout "I;" "assign_issue(): start, assign $ISSUEKEY to $JIRAUSER "
get_jirausers
JIRAUSERALLOWED=0
 # Loop through all values in an associative array
for ACC in "${ASSTABLEARR[@]}"; do 
    echoout "I;" "assign_issue(): test got arg \"$JIRAUSER\" are in array of jira users \"$ACC\" "
    if [[ $ACC == $JIRAUSER ]]; then
        echoout "I;" "assign_issue(): required user found: $ACC"
        JIRAUSERALLOWED=1
        break
    fi
done
if [[ $JIRAUSERALLOWED -eq 1 ]]; then
     echoout "I;" "assign_issue(): can continue"
else
     echoout "I;" "assign_issue(): presented user $JIRAUSER not found in list of allowed users"
    exit 0
fi
check_jirauser $JIRAUSER
DATAVAR=$( jq -c -n --arg name "$JIRAUSER" '{ $name }' )  
echoout "I;"  "json for assign: $DATAVAR"
echoout "I;" "assign_(): call jira api /issue to assign login $JIRAUSER to issue $ISSUEKEY "
curl_call "PUT"  "basic" "noresp" "data" "$JIRADSO_AUTH" "$DATAVAR" "$JIRADSO_URL/rest/api/2/issue/$ISSUEKEY/assignee"
if [[ "$CURLCODE" -ne "204" ]]; then
     echoout "E025;" "assign_issue(): NOT assigned issue in Jira (fail), HTTP status code $CURLCODE"
fi 
}

search_in_jira() {
RESEARCH="$1"
echoout "I;" "search_in_jira(): start, arg ^$RESEARCH^, search for ticket where MLH=$MLHNUM in $JIRADSO_URL"
## -s: silent -S: show errors when silent
curl_call "GET"  "basic" "resp" "nodata" "$JIRADSO_AUTH" "" "$JIRADSO_URL/rest/api/2/search?jql=cf[11000]~$MLHNUM"
if [[ "$CURLCODE" -ne "200" ]]; then
   echoout "E289;" "search_in_jira(): NOT sucessful search in Jira, HTTP status code $CURLCODE"
   exit 0 
else
    TOTAL=$( echo "$CURLBODY"| jq .total )
    echoout "I;" "search_in_jira(): successful search $TOTAL issues, save to $SRCHRESFILE"
    echo "$CURLBODY" > $SRCHRESFILE
    if [[ $RESEARCH == "research" ]]; then
       echoout "I;" "search_in_jira(): got re-search, save to files (^ is dividers, not var parts): ^$ISSUEKEY^, ^$ISSUEID^"  
       echo $ISSUEKEY > $SRCHRESKEY
       echo $ISSUEID > $SRCHRESID
    fi   
fi
}

search_issue_formlh() {

echoout "I;" "search_issue_formlh(): start "
#Strip string
MLHNUM=${COMMIT#MLH-}
if check_vendor; then
    echoout "I;" "search_issue_formlh(): check_vendor() result: vendor: ^$VENDOR^ good, continue"
else
    echoout "E;" "search_issue_formlh(): check_vendor() result: vendor: ^$VENDOR^ bad, exit"
    exit 0
fi  
search_in_jira
if [[ $TOTAL -eq 0 ]]; then
##    echoout "E292;" "searchissueformlh(): Not found issue with MLH (11000) ~ $MLHNUM"
    echo "Notfound" > $SRCHRESKEY
    ## for "separate letter" as promised in E292, which send if $JIRACHKRESFILE found
    echo "Не найдена задача с полем MLH (11000) ~ $MLHNUM" > $JIRACHKRESFILE
    if [[ $NO_DELIVERY != "true" ]]; then 
        echo "Поэтому будет запущено создание новой задачи" >> $JIRACHKRESFILE
        create_issue   
        echo "Создана новая задача $ISSUEKEY с полем MLH (11000) = $MLHNUM" >> $JIRACHKRESFILE
        echo "Назначена на \"$AUTHOR\", ссылка: $JIRADSO_URL/browse/$ISSUEKEY" >> $JIRACHKRESFILE
        search_in_jira research
    else
        echoout "I;" "searchissueformlh(): NO_DELIVERY=$NO_DELIVERY, then go to end of script"
    fi          
elif [[ $TOTAL -gt 1 ]]; then
    # join (-j) all keys into one string
    ISS=$( echo "$CURLBODY"| jq -jr '(.issues[]|" ",.key)' )
##    echoout "E292;" "searchissueformlh(): Found more than 1 issue with  MLH=$MLHNUM: $ISS"
    echo "Найдена более чем 1 задача MLH (11000) ~ $MLHNUM : $ISS" > $JIRACHKRESFILE
    for ((i=0; i<TOTAL; i++)); do
        check_issue_json $i 
    done
        if [[ ${#EXITMESS[@]} -gt 0 ]]; then
            for line in "${EXITMESS[@]}"; do
                echoout "E;" "$line"
                echo "- $line" >> $JIRACHKRESFILE
            done
        fi
    echo "Manyfound" > $SRCHRESKEY    
    exit 0    
else
    ISSUEKEY=$( echo "$CURLBODY" | jq -r .issues[0].key )
    ISSUEID=$( echo "$CURLBODY" | jq -r .issues[0].id )
    echoout "I105;" "searchissueformlh(): found $TOTAL issue, it key/id $ISSUEKEY/$ISSUEID. Save search json to artifact."
    echoout "I;" "search_issue_formlh(): save to files (^ is dividers, not var parts): ^$ISSUEKEY^, ^$ISSUEID^"
    echo $ISSUEKEY > $SRCHRESKEY
    echo $ISSUEID > $SRCHRESID
fi
}



check_issue_json() {
IND=0
[[ -n $1 ]] && IND=$1

ISSUEKEY=`echo $SRCHRES | jq -r .issues[$IND].key`
TYPENAME=`echo $SRCHRES | jq -r .issues[$IND].fields.issuetype.name`
PROJKEY=`echo $SRCHRES | jq -r .issues[$IND].fields.project.key`
ISSMOD=`echo $SRCHRES | jq -r .issues[$IND].fields.customfield_11001.value`
CURSTATUS=`echo $SRCHRES | jq -r .issues[$IND].fields.status.id`
#echo "$CURSTATUS" > $ISSTATUSFILE

echoout "I;" "check_issue_json(): index $IND, issue $ISSUEKEY, check project, module, type, status -> EXITMESS[]"
if [[ "$PROJKEY" != "PR268" ]]; then
     EXITMESS+=( "$ISSUEKEY: Неверный проект $PROJKEY != PR268" )
     echoout "E;" "wrong project $PROJKEY"
fi
if [[ "$ISSMOD" != "Somebase Host" ]]; then
     EXITMESS+=("$ISSUEKEY: Неверный модуль $ISSMOD != Somebase Host" )
     echoout "E;" "wrong module $ISSMOD"
fi
if [[ "$TYPENAME" != "Разработка" && "$TYPENAME" != "Доработка" && "$TYPENAME" != "Тест-дефект"  ]]; then
     EXITMESS+=( "$ISSUEKEY: Неверный тип $TYPENAME : не Разработка, Доработка или Тест-дефект" )
     echoout "E;" "wrong type $TYPENAME"
fi

### "issue status" records used in grep in changestatus() to get current status
case "$CURSTATUS" in
        "1" )
            #EXITMESS+=( "$ISSUEKEY: Статус = OPEN(открыто), не получится перевести в TESTING (передано в УВИТ), надо не забывать ставить статус INPROGRESS (в работе)")
            echoout "E;" "wrong issue status 1: \"open\""
            [[ $IND -eq 0 ]] && ./scripts/jira-api-search-do.sh changestatus "inprogress"
            if grep -q 'SUCCESS api call status transition' $CI_JOB_NAME.stderr; then
                EXITMESS+=("$ISSUEKEY: статус сменен на статус INPROGRESS автоматически")
                echoout "E;" "check_issue_json(): Got successful transition message, status changed"
                # for grepping in 'Notification' when changestatus() to testing    
                echoout "I;" "now right issue status 3: \"inprogress\""
            else
                echoout "E;" "check_issue_json(): Cannot grep 'successful transition message', status remains same"
            fi
        ;;
        "3" )
            echoout "I;" "right issue status 3: \"inprogress\""
        ;;
        "10100" )
          #  EXITMESS+=("$ISSUEKEY: статус = TODO(Надо сделать), не получится перевести в TESTING (передано в УВИТ), надо ставить статус INPROGRESS (в работе)")
            echoout "E;" "wrong issue status 10100: \"todo\""
            [[ $IND -eq 0 ]] && ./scripts/jira-api-search-do.sh changestatus "inprogress"
            if grep -q 'SUCCESS api call status transition' $CI_JOB_NAME.stderr ; then
                EXITMESS+=("$ISSUEKEY: статус сменен на статус INPROGRESS автоматически")
                echoout "E;" "check_issue_json(): Got successful transition message, status changed"
                # for grepping in 'Notification' when changestatus() to testing
                echoout "I;" "now right issue status 3: \"inprogress\""
            else
                echoout "E;" "check_issue_json(): Cannot grep 'successful transition message', status remains same"
            fi     
        ;;
        "10714" )
            EXITMESS+=( "$ISSUEKEY: Уже в статусе TESTING (передано в УВИТ), пайплайн запущен не первый раз" )
            echoout "E;" "wrong issue status 10714: \"testing\""
        ;;
        "10002" )
            EXITMESS+=("$ISSUEKEY: Уже в статусе DONE (выполнено), пайплайн запущен не первый раз")
            echoout "E;" "wrong issue status 10002: \"done\""
        ;;
        * )
            EXITMESS+=("$ISSUEKEY: Неизвестный статус у задачи, id  = $CURSTATUS" )
            echoout "E;" "wrong Unknown status $CURSTATUS"
esac

}

check_issue() {

if check_vendor; then
    echoout "I;" "check_issue(): check_vendor() result: vendor: ^$VENDOR^ good, continue"
else
    echoout "E;" "check_issue(): check_vendor() result: vendor: ^$VENDOR^ bad, exit"
    exit 0
fi   
load_issuekey
check_issue_json

if [[ ${#EXITMESS[@]} -gt 0 ]]; then
    #     echoout "E;" "${EXITMESS//$'\\n'}"
#echoout "E292;" "Search found errors in Jira-DSO:"
    for line in "${EXITMESS[@]}"; do
        echoout "E;" "- $line"
    echo "$line" >> $JIRACHKRESFILE
    done
else
    echoout "I106;" "after check_issue(): project, module, type, status ok"
 fi
}

##----------------------------- main -------------------

echoout "I;" "Start $0 $*"
if [[ "$#" -lt "1" ]]; then
    echoout "E290;" "Too few arguments. {command} required, see usage"
    print_usage
    exit 0
fi    

COMMAND=$1
ISSKEY=$2
JIRALOGIN=$3
## if second argument absent, env var is cleared
#COMMIT=$2
case "$COMMAND" in
    "searchissueformlh" )
        search_issue_formlh
    ;;
    "checkissue" )
        check_issue
    ;;
    "assignissue" )
        assign_issue $ISSKEY $JIRALOGIN
    ;;
    * )
        echoout "E291;" "command not suitable : $COMMAND"
        print_usage
esac

