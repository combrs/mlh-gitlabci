#!/bin/bash

CURDIR=`pwd`
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
#CI_JOB_NAME=${CI_JOB_NAME:-"Gen-json"}
CI_JOB_NAME=${CI_JOB_NAME:-"Notification"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}
CI_PUSH_TOKEN=${CI_PUSH_TOKEN:-"U3hTxJnPszhKZkLgYPxV"}
CI_PIPELINE_ID=${CI_PIPELINE_ID:-"274634"}
RELNOTESDIR=${RELNOTESDIR:-$CI_PROJECT_DIR}
COMMIT=${COMMIT:-"MLH-3694"}
COMHEAD=${COMHEAD:-"commheader.txt"}
## need for envsubst in gen_err_table()
## works also if $COMMIT defined later 
export COMMIT
MAIL_LIST=${MAIL_LIST:-"mlykov@mlh.ru"}
ERROR_MAIL_LIST=${ERROR_MAIL_LIST:-"mlykov@mlh.ru, mlh214277@dev.mlh"}
MAIL_LIST_REPORT=${MAIL_LIST_REPORT:-"mlykov@mlh.ru, mlh214277@dev.mlh"}
MAIL_LIST_ROBOT=${MAIL_LIST_ROBOT:-"mlh214277@dev.mlh"}
DEBUG_MAIL=${DEBUG_MAIL:-"mlykov@mlh.ru, mlh214277@dev.mlh"}
P_SEND_NOTIFICATION=${P_SEND_NOTIFICATION:-"false"}
HAPPYPATH=${HAPPYPATH:-"K3"}
SUPPLYURL="/release/$COMMIT/ST_$COMMIT.zip"
#EXTS=(txt json doc docx xls xlsx log)
## replaced in gen_mail()
EXTS=(data.json *.doc *.docx *.xls *.xlsx *.log artifacts.zip )
#ISSTYPES=(OS- BR- TST- IMPL-)
ISSTYPES=${ISSTYPES:-"OS- BR- TST- IMPL-"}
export ISSTYPES
MAILJSONFILE=${MAILJSONFILE:-"mail.json"}
MAILJIRAWARNJSONFILE=${MAILWARNJSONFILE:-"mail-jirawarn.json"}
JIRAGLHJSONFILE=${JIRAGLHJSONFILE:-"jira.json"}
PIPERESJSONFILE=${PIPERESJSONFILE:-"piperesult.json"}
DEPLOYRESFILE=${DEPLOYRESFILE:-"deploy_result-$COMMIT.txt"}
ANSIBLERESFILE=${ANSIBLERESFILE:-"ansible_result-$COMMIT.txt"}
ERRTABLEFILE=${ERRTABLEFILE:-"errtable.txt"}
DEPLOYCHECKERRFILE=${DEPLOYCHECKERRFILE:-"check-notok.txt"}
JIRACHKRESFILE=${JIRACHKRESFILE:-"jiradso.chkres"}
CPAGECHKFILE=${CPAGECHKFILE:-"cpagechk.txt"}
READMESFILE=${READMESFILE:-"readmesexcess.json"}
RESDIFFFILE=${RESDIFFFILE:-"resdiffsha1.txt"}
TESTSRESULT=${TESTSRESULT:-"numtests.txt"}
JIRADSO_URL="http://task.corp.dev.mlh"
GITLABURL=${GITLABURL:-"http://ci.corp.dev.mlh/api/v4/"}
CONFDSO_USER=${CONFDSO_USER:-"dso-prf-system-ads"}
CONFDSO_PASS=${CONFDSO_PASS:-"Bipj0jLa"}
CONF_AUTH=`echo -n $CONFDSO_USER:$CONFDSO_PASS|base64`
CONF_URL="http://wiki.corp.dev.mlh/rest/api/content"

NEXUS_URL=${NEXUS_URL:-"http://nexus.corp.dev.mlh"}
NEXUS_DEV=${NEXUS_DEV:-"develop"}
NEXUS_REL=${NEXUS_REL:-"release"}
NEXUSRESFILE=${NEXUSRESFILE:-"nexussearchres.json"}
NEXUS_USER=${NEXUS_USER:-"cds"}
NEXUS_PASS=${NEXUS_PASS:-"1qazXSW@3edcVFR$"}

NEXUS_AUTH=$( echo -n $NEXUS_USER:$NEXUS_PASS|base64 )
NEXUS_SEARCHPATH="distribs/${NEXUS_DEV}/${COMMIT}"
NEXUS_REMOVEPATH="distribs/${NEXUS_DEV}/${COMMIT}/"
NEXUS_DEVPATH="${NEXUS_URL}/repository/somebase/distribs/${NEXUS_DEV}"
NEXUS_RELPATH="${NEXUS_URL}/repository/somebase/distribs/${NEXUS_REL}"

SMTP_FROM="dso-prf-system-ads@dev.mlh"

source ./scripts/common_func.sh
print_usage () {
	    PROG=`basename $0`	
	
            echo "Usage:
               $PROG genformail  - generate json for mail list about installed supply (save it and post with curl -d @file)
               $PROG genforjiraglh  - generate json to post to Jira GLH
		       $PROG genforjiraglherror  - generate \"delivery failed\" json for send to JIRA GLH comment
	           $PROG genformailfile  {MAIL LIST} {SUBJECT} {FILE} - get FILE and generate json with its content, that subject and recipients
	           $PROG genforpipelineerrormail - generate json for error mail letter
	           $PROG genforjirawarn - generate json for letter about absent tasks in JIRA DSO (and other err)
	           $PROG genattestresult - generate letter with failed attest list (with genformailfile)
               $PROG genformailerr  - generate letter with some steps instead genforpipelineerrormail
               $PROG generrtable - generate errtable.txt file from confluence wiki" 
}




add_scope_delivery() {
if [[ ! -f $COMMIT.txt  ]]; then
    echoout "E011;" "add_scope_delivery(): NOT found $COMMIT.txt, cannot generate any json"
    exit 1
fi
rm -f $COMMIT-scope.txt

## space before scope of delivery
echoout "I;" "add_scope_delivery(): start. copy from CR_contents.txt to $COMMIT-scope.txt"
echo >> $COMMIT-scope.txt
echo -en "Scope of delivery:\r\n" >> $COMMIT-scope.txt
echo -en "-------------------------------\r\n" >> $COMMIT-scope.txt
if [ -f "CR_contents.txt" ]; then
    echoout "I;" "add_scope_delivery(): CR_contents.txt found, add first 3 fields"
    grep -v "#" CR_contents.txt| while read -r line
    do
        echo -n $line|awk -F'|' '{print $1"|"$2"|"$3}'| sed "s/$/\r/"
    done >> $COMMIT-scope.txt
else
    ls -l
    echoout "E609;" "add_scope_delivery(): Cannot find extracted CR_contents.txt here"
    exit 1
fi
}

make_attaches() {
    echoout "I;" "make_attaches_json(): start"
    echo "[]" > att0.json
    IND=0
    ATTS=()
    LSFILES=$( ls "${EXTS[@]}" 2>/dev/null )
    FILESARR=( "$LSFILES" )
    IFS=$'\n'
    for FILEP  in ${FILESARR[@]}; do
        echoout "I;" "make_attaches_json(): generate attach json for file $FILEP"
        BASE64FILE=$( echo "{\"body\": \"$( base64 -w 0 $FILEP )\" }" )  #"..
        echo "{\"name\":\"$FILEP\", \"format\":\"base64\"}" |  jq --slurpfile BODY <( printf "%s\n" $BASE64FILE )  '. += ($BODY[0])' > $FILEP.jsonbase
        jq ".[${IND}] += input" att${IND}.json $FILEP.jsonbase > att$((IND+1)).json
        rm -vf att${IND}.json
        rm -vf $FILEP.jsonbase
        IND=$((IND+1))
        ATTS+=("-a" "$FILEP")
    done
echoout "I;" "make_attaches_json(): attach.json ready (merged), $IND files"
mv -vf att${IND}.json attach.json
}

gen_jiraids() {
echoout "I;" "gen_jiraids(): start"
#    sed -i "s/\r//" $COMMIT.txt
#       taken from $COMHEAD
#    JIRA_ID=$( grep 'JIRA ID' $COMMIT.txt | cut -d':' -f 2 | tr "," " " )
    echoout "I;" "gen_jiraids(): will take jiraids: $JIRA_ID"
    JIRAIDS="[]"
    for JIRAID in $JIRA_ID; do
       JIRAIDS=`echo $JIRAIDS | jq ". + [\"$JIRAID\"]"`
    done
    echoout "I;" "gen_jiraids(): taken JIRA IDS ${JIRAIDS//$'\n'}"
          
}
check_goodend() {
echoout "I;" "check_goodend(): start"
echoout "I;" "check_goodend(): try to grep I112 in $CI_JOB_NAME.stderr, see next line (present or not)"
if grep '^I112;' $CI_JOB_NAME.stderr; then
    BODY=${BODY}$( echo -e "\r\n\r\n"; echo  "Процесс сборки и отправки успешно завершен, письмо с data.json в JIRA-IT отправлено" )
    BODY=${BODY}$( echo -e "\r\n"; echo  "(pipeline #${CI_PIPELINE_ID}(${CI_PIPELINE_SOURCE}), запустил ${GITLAB_USER_NAME} [${GITLAB_USER_EMAIL}] )" )
#"
     if [[ -n $P_CHECK_REDELIVERY && $P_CHECK_REDELIVERY != "true" ]]; then
        BODY=${BODY}$( echo -e "\r\n"; echo  "Этап проверки перепоставки был отключен" )
     fi
    if [[ -n $P_DEPLOY && $P_DEPLOY != "true" ]]; then
        BODY=${BODY}$( echo -e "\r\n"; echo  "Этап  установки  был отключен" )
    fi
    if [[ -n $P_DEPLOY_CHECK && $P_DEPLOY_CHECK != "true" ]]; then
        BODY=${BODY}$( echo -e "\r\n"; echo "Этап проверки лога установки был отключен" )
    fi    
    if [[ -n $P_TESTS && $P_TESTS != "true" && $P_TESTS != "fail" ]]; then
        BODY=${BODY}$( echo -e "\r\n"; echo "Этап автотестирования был отключен" )
    fi
    if [[ -n $P_TESTS && $P_TESTS == "fail" ]]; then
        BODY=${BODY}$( echo -e "\r\n"; echo "Этап автотестирования принудительно включен в статус ошибочного" )
    fi
    ERWCH=$( grep 'WARNING' check.txt ); GREX=$?
    if  [[ "$GREX" -eq "0" ]]; then
        echoout  "E304;" "check_goodend(): WARNING word found in check results"
    
        BODY=${BODY}$( echo -e "\r\n\r\n"; echo "Найдены предупреждения в логе проверки установки:" )
        BODY=${BODY}$( echo -e "\r\n"; echo "${ERWCH}" | sed "s/$/\r/"; echo -e "\r\n\r\n"; )
    fi   
else
    echoout "I;" "check_goodend(): Did not find I112 (successful send mail for jira-it) marker in file $CI_JOB_NAME.stderr"
fi

}

gen_mail_header() {
echoout "I;" "gen_mail_header(): start"
# take json array from file
gen_jiraids
JIRAIDS=$( echo "$JIRAIDS" | tr -d "\r\n" )
BODY=$( echo -e "\r\nАвтор: $AUTHOR\r\nВендор: $VENDOR\r\nJira ID(s): $JIRAIDS\r\nСборка из: $BRANCH\r\nКоммитер: $COMMITER\r\nРелиз: $RELEASE\r\n" )
#"
if [[ -f $DEPLOYRESFILE ]]; then
    while read FULLDEPRES; do
        BASE=$( echo "$FULLDEPRES"| cut -d- -f 1 )
        HOST=$( echo "$FULLDEPRES"| cut -d- -f 2 )
        BODY=${BODY}$( echo -e "\r\nБаза: $BASE\r\nСтенд: $HOST" )
    done < $DEPLOYRESFILE    
else 
    echoout "E;" "gen_mail_header(): Did not found deploy res file $DEPLOYRESFILE when add host/base to good mail. that strings will be empty"
fi
}

gen_for_mail_smtp() {
ARGFILE="$1"
SENTMAIL="$ARGFILE.rfc822"
echoout "I;" "gen_for_mail_smtp(): save mail file to ^$SENTMAIL^ with subj ^$SUBJ^ to ^$RECIPSMTP^"
if [[ -n "$SUBJ" && -n "$RECIPSMTP" && -n "$BODY" ]]; then
    BODY1=$( tr -d '\r' <<<"$BODY"  )
    if [[ "${#ATTS[@]}" -gt 1 ]]; then
        echoout "I;" "gen_for_mail_smtp(): mail with ^$((${#ATTS[@]}/2))^ attaches"
        mail -S sendmail=/bin/true -S record="$SENTMAIL" -s "$SUBJ" -r "$SMTP_FROM" "${ATTS[@]}" "$RECIPSMTP" <<<"$BODY1"
    else
        echoout "I;" "gen_for_mail_smtp(): no attaches names prepared"
        mail -S sendmail=/bin/true -S record="$SENTMAIL" -s "$SUBJ" -r "$SMTP_FROM" "$RECIPSMTP" <<<"$BODY1"
    fi    
else
    echoout "I;" "gen_for_mail(): lack of some args for RFC822 mail: subj  or to or body"
fi

}

gen_for_mail() {
echoout "I;" "gen_for_mail(): start"
SUBJ=$( echo $SUBJ |tr -d '#\r\n' )
# prepare readme file with join scope of delivery to end
add_scope_delivery
ARG=$1
if [[ $ARG == "robot" ]]; then
    echoout "I;" "gen_for_mail(): Have an argument "$ARG", therefore generate mail to Jita-IT robot"
    MAILJSONFILE="robot-"${MAILJSONFILE}
    MAIL_LIST=$MAIL_LIST_ROBOT
    EXTS=( data.json *.doc *.docx *.xls *.xlsx )
    SUBJ="$COMMIT $SUBJ "
    BODY=$( echo -e "Author: $AUTHOR\r\nVendor: $VENDOR\r\n" )
    gen_jiraids
else
    echoout "I;" "gen_for_mail(): without argument, generate for human with additional text"
    EXTS=( data.json )
    SUBJ="$COMMIT: Поставка успешна  ( $SUBJ )"
    gen_mail_header
    check_goodend
    # extract comment urls from all stderr files
    cat_all_stderr
fi

rm -vf $MAILJSONFILE || true

## defined above
#    SUBJ=$( grep Title $COMMIT.txt | cut -d':' -f 2 )
#    SUBJ=${SUBJ:1} # Strip first space comes from file - see next string 
#    SUBJ="$COMMIT "$( echo $SUBJ |tr -d '#\r\n' )
    SUBJJ=`jq -n --arg subj "$SUBJ" '{subject: $subj}'`
    ## use sed to add windows EOL
#    BODY=$( echo -e "Author: $AUTHOR\r\nVendor: $VENDOR\r\n" )
### newline between 'pipeline, run by user' and 'Description' from readme file
    BODY=${BODY}$( echo -e "\r\n" )
    BODY=${BODY}$( grep -vEi 'Title|Author|Vendor|JIRA|Release' $COMMIT.txt | sed "s/$/\r/" )
    BODY=${BODY}$( cat $COMMIT-scope.txt )
    RECIP=$(get_mails "$MAIL_LIST")
    echoout "I:" "gen_for_mail(): get_mails made list: ${RECIP//$'\n'}"
    echoout "I;" "gen_for_mail(): Mail subject will be: \"$SUBJ\""
    echoout "I;" "gen_for_mail(): Mail body will be: \"$BODY\""
    BODYB=`echo "$BODY"|base64 -w 0`
   
jq -n "{vendor: \"INHOUSE\",system: \"PF-Dev\",version: \"$COMMIT\", Release: \"$RELEASE\",
  supplyPath: [ \"$SUPPLYURL\" ], issues: $JIRAIDS, happyPath: [ \"$HAPPYPATH\" ],
  component: \"DSO-Pilot\",  shouldTestUI: \"false\", md5Required: \"false\", shouldTestIntegration: \"false\",
  regression: { type: \"none\", businessProcess: [] }, autoDeployOnProd: \"false\",
  desc: \"test\", cumulative: \"true\",  dependsOn: \"\" }" > $CI_PROJECT_DIR/data.json

cd $CI_PROJECT_DIR
make_attaches
echo "{}" > tempmail.json
echo $SUBJJ > subj.json
echo $BODY > body.mail

echoout "I;" "gen_for_mail(): combine header for $MAILJSONFILE with common file attach.json for all attaches"
## \"attachments\": input }" tempmail.json attach.json - first is input for add, second is {input} for tag
## unix stackexchange 460985
jq "{recipient: $RECIP, body: \"$BODYB\", \"attachments\": input }" tempmail.json attach.json > tempmail2.json
## stackoverflow 19529688
jq -s '.[0] * .[1]' subj.json tempmail2.json > $MAILJSONFILE
rm -vf tempmail.json tempmail2.json subj.json attach.json

RECIPSMTP=$(get_mails "$MAIL_LIST" "smtp")
echoout "I:" "gen_for_mail(): get_mails made list for smtp: ${RECIPSMTP//$'\n'}"
gen_for_mail_smtp ${MAILJSONFILE%.json}

}


declare -A ERRTABLEARR
gen_err_table() {
echoout "I;" "gen_err_table(): start with args \"$*\""

if [[ -f  "$CI_PROJECT_DIR"/$ERRTABLEFILE ]]; then
    echoout "I;" "gen_err_table() : $ERRTABLEFILE Already exist, skip curl request to jira"
    
else
    echoout "I;" "gen_err_table() : try to curl wiki table"
    curl_call "GET"  "basic" "resp" "nodata" "$CONF_AUTH" "" "$CONF_URL/31558546?expand=body.storage"
    if [[ "$CURLCODE" -ne "200" ]]; then
        echoout "E;" "gen_err_table():  NOT sucessful get table from Jira, HTTP status code $CURLCODE, get file from mail/"
        cp -vf "$CI_PROJECT_DIR"/mail/$ERRTABLEFILE "$CI_PROJECT_DIR"
    else
        echoout "I;" "gen_err_table() : get table from confluence HTTP status code $CURLCODE"
    ## '$' in sed replacement means there is escape sequence after it, stackoverflow unknown question
        ERRTABLE=`echo "$CURLBODY" | jq '.body.storage.value' | sed 's#</tr>#\'$'\n#g' | grep -E 'E[0-9]{3}'` 
        echo "$ERRTABLE" | awk -F "<td" '{print $2"#"$3}' | sed -r 's#(colspan=\\"1\\">|</td>|>|</?span|</?p|&quot;|&nbsp;|class=\\"nolink\\")##g' > "$CI_PROJECT_DIR"/$ERRTABLEFILE
        echoout "I;" "gen_err_table(): generated file $ERRTABLEFILE"
    fi
fi # if file exist    
    OLDIFS=$IFS
    while read line; do
    #   echo llll $line
        IFS='#' read V1 V2 <<< $line
    #   echo z111 "-$V1-" zz222 "$V2"
    #   echo zzzzz $( echo $V2 | envsubst )
        if [ -n "$V1" ]; then 
            # remove spaces from keys, if any
    	   V1=${V1// /}
            ## envsubst taken from stackoverflow #10683349
    	   ERRTABLEARR[$V1]="$(echo $V2 | envsubst )"
        fi
    done < <(grep -E 'E[0-9]{3}' "$CI_PROJECT_DIR"/$ERRTABLEFILE )
    IFS=$OLDIFS
    echoout "I;" "gen_err_table(): end filling ERRTABLEARR assoc array, ${#ERRTABLEARR[*]} elements"
    #echoout "I;" "ERRTABLEARR elements: ${!ERRTABLEARR[*]}"
}

cat_all_stderr() {
echoout "I;" "cat_all_stderr(): start with args \"$*\", Try to cat ./*.stderr files"
ARG=$1
if cat ./*.stderr > pipeline-stderr.txt; then
     if [[ $CI_JOB_NAME == "Error_notification" ]]; then
        echoout "I;" "cat_all_stderr(): files cated, call gen_errmail_from_errfile()"
        gen_errmail_from_errfile pipeline-stderr.txt
        get_comment_urls pipeline-stderr.txt
## also called to cat files in changestatus(), but not need to add anything to $BODY
     elif [[ $CI_JOB_NAME == "Notification" && $ARG != "changestatus" ]]; then
         echoout "I;" "cat_all_stderr(): files cated, call gen_for_mail() for humans"
        get_comment_urls pipeline-stderr.txt
     else
        echoout "I;" "cat_all_stderr(): files cated, but job name not 'Error_notification' nor 'Notification' or called for changestatus()(see start), skip gen_errmail/get_comment"
     fi   
else
    echoout "E;" "cat_all_stderr(): Did not find any stderr files for cat and detail errors, send only Vendor/Author/branch(/url if any) message"
fi

}

get_comment_urls() {
echoout "I;" "get_comment_urls(): start with args \"$*\" "
if [[ "$#" -lt "1" ]]; then
    echoout "E;" "get_comment_urls(): Too few arguments. {file} to get urls from required, see usage"
    print_usage
    exit 0
fi  
FILE=$1
if [ ! -f "$FILE" ]; then
    echoout "E;" "get_comment_urls(): Did not find file $FILE to generate comment urls"
    exit 0
fi
    COMMURLS=$( grep "$COMMIT COMMENTURL;" $FILE | cut -d' ' -f 5- | sort -u | sed "s/$/\r/" )
    if [ -n "$COMMURLS" ]; then
        COMMURLSLINES=$( echo "$COMMURLS" | wc -l )
        echoout "I;" "get_comment_urls(): Add comment urls: $COMMURLSLINES lines to BODY from file: $FILE"
#        echo "$BODY" > body-before-commurls.txt
## \r\n at the end "" did not work (print only \r)
        BODY=${BODY}$( echo -e "\r\n\r\nЗапощеные комментарии в JIRA-DSO: "; echo -e "\r\n" )
#        echo "$COMMURLS" > body-commurls.txt
        BODY=${BODY}"$COMMURLS"
#        echo "$BODY" > body-with-commurls.txt
    else
        echoout "I;" "get_comment_urls(): No comment urls in this file: $FILE"
    fi
}    

gen_errmail_from_errfile() {
echoout "I;" "gen_errmail_from_errfile(): start with args \"$*\""
ERRFILE=$1
if [ ! -f "$ERRFILE" ]; then
    echoout "E;" "gen_errmail_from_errfile(): Did not find errfile $ERRFILE to generate errormail from it"
    exit 0
fi
    while read linestage; do
        echoout "I;" "gen_errmail_from_errfile(): Found error $linestage in stderr files, add translated mess from array if any"
        line=${linestage::4}
        ERRSTAGE=$( echo $linestage | cut -d' ' -f 2 )  
        P_ERRNUMS+=( $line ) 
#	echo "line value --$line--"
#	echo " table value --${ERRTABLEARR[$line]}--"
	if [[ "$line" == "E101" ]]; then
	    P_ERRS+=( "${ERRTABLEARR[$line]}" )
	    echoout "I;" "gen_errmail_from_errfile(): redelivery array value ${ERRTABLEARR[$line]} for err $line"
	    SUBJ="[pipeline $CI_PIPELINE_ID ] Дубликат поставки $COMMIT"
	    echoout "I;" "gen_errmail_from_errfile(): Set  special subj because err = $line"
	    ./scripts/jira-api-search-do.sh postcomment "Redelivery detected on $NEXUS_RELPATH/$COMMIT/ST_$COMMIT.zip, job name $CI_JOB_NAME, started by user $GITLAB_USER_NAME, details url $CI_JOB_URL"
	elif [[ "$line" == "E104" ]]; then
	    ## use "output only match" and "use perl-like regexp with lookforward and lookbehind" (stackexchange #13466)
	    NEXUSBUGFILE=`grep '^E104;' $ERRFILE | grep -oP '(?<=got ).*(?= remove)' | sed "s/$/\r/" `
	    NEXUSBUGFILE=${NEXUSBUGFILE::-1}
	    P_ERRS+=( "${ERRTABLEARR[$line]} Файл: \"$NEXUSBUGFILE\"" )
	    echoout "E;" "gen_errmail_from_errfile(): add about (nexus bug) file $NEXUSBUGFILE"
    elif [[ "$line" == "E112" ]]; then
        ## use "output only match" and "use perl-like regexp with lookforward and lookbehind" (stackexchange #13466)
        NEXUSBUGFILE=`grep '^E112;' $ERRFILE | grep -oP '(?<=nexussearch found item ).*(?=, but)' | sed "s/$/\r/" `
        NEXUSBUGFILE=${NEXUSBUGFILE::-1}
        P_ERRS+=( "${ERRTABLEARR[$line]} Файл: \"$NEXUSBUGFILE\"" )
        echoout "E;" "gen_errmail_from_errfile(): add about (nexus bug) file $NEXUSBUGFILE"
    elif [[ "$line" == "E115" ]]; then
        READMES=$( cat "$READMESFILE" )
        P_ERRS+=( "${ERRTABLEARR[$line]} ^$READMES^" )
	elif [[ "$line" == "E010" ]]; then    
        JIRAID=$( grep "^$line;"  $ERRFILE | tail -n 1 |cut -d'^' -f 2 )
        P_ERRS+=( "${ERRTABLEARR[$line]} $JIRAID" )    
	elif [[ -z ${ERRTABLEARR[$line]} ]]; then
	    echoout "E;" "gen_errmail_from_errfile(): Unknown error number $line, add to P_ERRS_UN[]"
	    P_ERRS_UN+=($line)
	    continue
    else
	    P_ERRS+=( "${ERRTABLEARR[$line]}" )
	    echoout "I;" "gen_errmail_from_errfile(): Simply add array value ${ERRTABLEARR[$line]} for err $line"
	fi
	## change last added element  = number of elements -1 for add err before line
	P_LEN=${#P_ERRS[@]}
	P_ERRS[$P_LEN-1]=${line}": $ERRSTAGE : "${P_ERRS[$P_LEN-1]}
    done < <(grep -E '^E[0-9]{3};' $ERRFILE | cut -d ' ' -f 1-2 | sort -u )

    [ ${#P_ERRS[@]} -gt 0 ] && echoout "I;" "gen_errmail_from_errfile(): Add ${#P_ERRS[@]} lines of errors to BODY"  
    BODY=${BODY}$( echo -e "\r\n"; printf '%s\r\n' "${P_ERRS[@]}" )
    if [[ "${#P_ERRS_UN[@]}" -gt 0 ]]; then
    	echoout "I;" "gen_errmail_from_errfile(): Add ${#P_ERRS_UN[@]} lines of UNKNOWN errors to BODY"
        BODY=${BODY}$( echo -e "\r\n Неизвестные ошибки:\r\n" )
		for E in "${P_ERRS_UN[@]}"; do
	    	BODY=${BODY}$( grep -E '^E[0-9]{3};' $ERRFILE | grep  ^$E | sort -u )
		done
    fi
    if [ -f "$DEPLOYCHECKERRFILE" ]; then
		BODY=${BODY}`echo -e "\r\nСодержимое файла проверки лога инсталляции (повторяющиеся ошибки находятся в разных строках исходного файла)\r\n"`
		# remove empty lines (only \n)
		CHLOG=`grep -v '^$' check-notok.txt`
		CHLOGLINES=`echo $CHLOG | wc -l`
		echoout "I;" "gen_errmail_from_errfile(): Add checklog error result: $CHLOGLINES lines to BODY"
		# if ${BODY}${CHLOG}. then \n after BODY lost	
		BODY=$( echo "$BODY"; echo "$CHLOG" )
    fi
    if [[ -f $CPAGECHKFILE ]]; then
          echoout "I;" "gen_errmail_from_errfile(): Add list of files with wrong encoding $CPAGECHKFILE to mail body"
          BODY=${BODY}$( echo -e "\r\n"; echo -n "Список файлов в неверной кодировке или неверной длины имени из поставки:" )
          BODY=${BODY}$( echo -en "\r\n"; cat $CPAGECHKFILE | sed "s/$/\r/" )
          BODY=${BODY}$( echo -e "\r\n"; echo -n "Если они были в неверной кодировке, то перекодированы в UTF-8, архивированы в файл ST_MLH-$COMMIT-reenc.zip и приложены к письму внутри архива artifacts.zip"; echo -e "\r\n" )
    fi        
}

gen_mail_from_subjbody() {
echoout "I;" "gen_mail_from_subjbody(): start "

## if not defined in gen_errmail_from_errfile() above
if [[ -z $SUBJ ]]; then
    SUBJ="[pipeline $CI_PIPELINE_ID ] Ошибки в поставке $COMMIT: "
    SUBJ=${SUBJ}${P_ERRNUMS[*]}
fi

RECIP=$(get_mails "$ERROR_MAIL_LIST")
## this used if send only autglhst result
##RECIP=$(get_mails "$MAIL_LIST_REPORT")
echoout "I:" "gen_mail_from_subjbody(): get_mails made list: ${RECIP//$'\n'}"
echoout "I;" "gen_mail_from_subjbody(): Mail subject will be: \"$SUBJ\""
echoout "I;" "gen_mail_from_subjbody(): Mail body will be: \"$BODY\""
echo "$BODY" > gen-body-mail.txt
BODYB=$( echo -e "$BODY"|sed "s/$/\r/" |base64 -w 0 )
if [[ -n "$STAGE_NAME" && "$STAGE_NAME" != "null" ]]; then
	echoout "I;" "gen_mail_from_subjbody(): Stage name not null, really attach log/artifact files to mail"
    cd $CI_PROJECT_DIR
    if [[ "$STAGE_NAME" == "Notification" ]]; then
        echoout "I;" "gen_mail_from_subjbody(): Stage name = Notification, attach only 'data.json' to success mail"
        EXTS=( data.json )
    fi    
	make_attaches
	echoout "I;" "gen_mail_from_subjbody(): combine header for $MAILJSONFILE with common file attach.json for all attaches"
	## \"attachments\": input }" tempmail.json attach.json - first is output, second is {input}
	#echo $SUBJJ | jq ". + {recipient: $RECIP, body: \"$BODY\", \"attachments\": input }" tempmail.json attach.json  > $MAILJSONFILE
	jq -n " {subject: \"$SUBJ\", recipient: $RECIP, body: \"$BODYB\", \"attachments\": input }" attach.json  > $MAILJSONFILE
else
	echoout "I;" "gen_mail_from_subjbody(): Stage name is null, not attach log/artifact files to mail"
	jq -n " {subject: \"$SUBJ\", recipient: $RECIP, body: \"$BODYB\"}" > $MAILJSONFILE
fi	

RECIPSMTP=$(get_mails "$ERROR_MAIL_LIST" "smtp")
echoout "I:" "gen_for_mail(): get_mails made list for smtp: ${RECIPSMTP//$'\n'}"
gen_for_mail_smtp ${MAILJSONFILE%.json}

}

gen_for_pipeline_errormail() {
echoout "I;" "gen_for_pipeline_errormail(): start "
echoout "I;" "gen_for_pipeline_errormail(): begin collect BODY from vendor, author, branch,base,host,jiraids in gen_mail_header()"
gen_mail_header
if [[ "$STAGE_NAME" != "null" ]]; then
	BODY=${BODY}$( echo -e "\r\nPipeline ветка $REF, Ошибки к выполнению этапа $STAGE_NAME, упавший Job # $JOB,\r\n URL $FAILED_JOB_URL\r\n" )
    curl_call "output"  "token" "noresp" "nodata" "$CI_PUSH_TOKEN" "" "$GITLABURL/projects/190/jobs/$JOB/trace" "trace.log"
	if [[ "$STAGE_NAME" !=  "Auto_testing" ]]; then
		echoout "I;" "gen_for_pipeline_errormail(): Error stage $STAGE_NAME, downloading artifacts for job $JOB"
        curl_call "output"  "token" "noresp" "nodata" "$CI_PUSH_TOKEN" "" "$GITLABURL/projects/190/jobs/$JOB/artifacts" "artifacts.zip"
	fi
else
	echoout "I;" "gen_for_pipeline_errormail(): stage name $STAGE_NAME, called for gen only file with errs without getting failed stage artifacts"
fi
## gen E800 err before cat stderr 
if [[ "$STAGE_NAME" == "Deploy"   ]]; then
        if [ -f $ANSIBLERESFILE ]; then
            echoout "E800;" "gen_for_pipeline_errormail(): found $ANSIBLERESFILE and error stage Deploy, split and add to BODY later"
            ANSIBLERES=`cat $ANSIBLERESFILE`
            IFSOLD=$IFS 
            IFS='-'
            ANSIBLEFAILARR=($ANSIBLERES)
            BODY=${BODY}$( echo -e "\r\n"; echo -n "Ansible failed in module \"${ANSIBLEFAILARR[0]}\" when action \"${ANSIBLEFAILARR[1]}\" on host \"${ANSIBLEFAILARR[2]}\" "; echo -e "\r\n" ) 
            IFS=$IFSOLD
        else
            echoout "I;" "gen_for_pipeline_errormail(): error stage =  Deploy, BUT $ANSIBLERESFILE NOT FOUND"
        fi  
fi  
# gen table before cat stderr because it can add errors by its own run
gen_err_table
## -i ignore case, -w ignore all whitespace, -B ignore blank lines
ERRDIFF=$( diff -iwB -U1 "$CI_PROJECT_DIR"/mail/$ERRTABLEFILE "$CI_PROJECT_DIR"/$ERRTABLEFILE  )
DIFFEX=$?
if [[ "$DIFFEX" -eq 1 ]]; then
    echoout "E606;" "gen_for_pipeline_errormail(): git ver mail/$ERRTABLEFILE differ from wiki ver $ERRTABLEFILE, see below "
    echoout "E606;" "gen_for_pipeline_errormail(): $ERRDIFF"
fi
cat_all_stderr
gen_mail_from_subjbody

rm -vf tempmail.json
}

## used in send_sendnotif_errs() 
# do less than gen_for_pipeline_errormail()

gen_for_mail_err() {
echoout "I;" "gen_for_mail_err(): start with args \"$*\""
ERRFILE=$1
if grep -qE '^E[0-9]{3};' $ERRFILE; then
        echoout "I;" "gen_for_mail_err():  found E* Errors in $ERRFILE"
        # call format: command commit errfile, $3=mails, see arg parsing for main script
        gen_err_table
        gen_errmail_from_errfile $ERRFILE
        get_comment_urls pipeline-stderr.txt
        gen_mail_from_subjbody
else
    echoout "E:" "gen_for_mail_err(): grep $ERRFILE do not find any errors"
fi
}

gen_for_jira_warn() {
echoout "I;" "gen_for_jira_warn(): start "

if get_job_info "success"; then
    echoout  "I;" "gen_for_jira_warn(): Did not found completed 'Error_notification' job, can continue"
else
    echoout  "E;" "gen_for_jira_warn(): Found completed 'Error_notification' job, pipeline $CI_PIPELINE_ID restarted, not send jirawarn mail again, return"
    return
fi
if  [ -f $JIRACHKRESFILE ]; then
    echoout "I;" "gen_for_jira_warn(): chkres file  $JIRACHKRESFILE found, errors found in Jira-DSO for $COMMIT" 
    CHKRES=$( cat $JIRACHKRESFILE )
    ISSUEKEY=$( echo $CHKRES | grep -oP '(?<=Создана новая задача ).*(?= с полем)' )
    CHANGESTAT=$( echo $CHKRES | grep -oP '(?<=сменен на статус ).*(?= автоматически)' )
#'
    if [[ -n $ISSUEKEY ]]; then
        SUBJ="$COMMIT : Создана задача $ISSUEKEY в JIRA-DSO"
    elif [[ -n $CHANGESTAT ]]; then
        SUBJ="$COMMIT : Сменен статус задачи на $CHANGESTAT"
    else
        SUBJ="$COMMIT : ошибки в JIRA-DSO для этой задачи"        
    fi 
#    if echo "$CHKRES" | grep '(11000)'; then
#       echoout "E;" "in chkres file: Issue not found in Jira-DSO for $COMMIT"
#        SUBJ=${SUBJ}" Не найдена задача в Jira-DSO $JIRADSOURL!"
#    fi
    gen_mail_header
#    BODYW="Поставка $COMMIT, Vendor $VENDOR, Автор $AUTHOR, branch $BRANCH"
    # BODY from func above
    BODYW=${BODY}$( printf "%s\n%s" "$BODYW" "$CHKRES" )
    if  [ -f $RESDIFFFILE ]; then
        RESDIFF=$( cat "$RESDIFFFILE" )
        echoout "I:" "gen_for_jira_warn(): diff builders file found: $RESDIFF"
        BODYW=${BODYW}$( echo -e "\r\n\r\nФайлы, различающиеся при сборке разными сборщиками (- : Java, +: python) "; echo -e "\r\n" )
#"
        BODYW=${BODYW}$( printf "%s\n%s" "$BODYW" "$RESDIFF" )
    fi
    SUBJJ=`jq -n --arg subj "$SUBJ" '{subject: $subj}'`
    echoout "I:" "gen_for_jira_warn(): subject will $SUBJ"
    # copy local errtable to not call jira
    ##[[ -f $CI_PROJECT_DIR/mail/$ERRTABLEFILE ]] && cp -vf $CI_PROJECT_DIR/mail/$ERRTABLEFILE $CI_PROJECT_DIR/$ERRTABLEFILE
    # BODY contains header from gen_mail_header above, will doubled.clear previous BODY (with header)
    BODY=""
    # errtable not generated before in success pipeline
    gen_err_table
    # based on file created in cat_all_stderr() in gen_for_mail() from mailv3.yml, called earlier for humans
    gen_errmail_from_errfile pipeline-stderr.txt
    # add result to generated common
    BODYW="${BODYW}${BODY}"
    if grep -qE '^E6[0-9]{2};' $CI_JOB_NAME.stderr; then
        echoout "E;" "gen_for_jira_warn(): Some errors occured now in job $CI_JOB_NAME, add it to jira warn file."
        gen_errmail_from_errfile $CI_JOB_NAME.stderr
        # BODY from func above
        BODYW="${BODYW}${BODY}"
    else
         echoout "I;" "gen_for_jira_warn(): No numbererrors occured now to add to jirawarn file"
    fi
    
    echo "$BODYW" > gen-body-warn.txt
    BODYB=$( echo "$BODYW"| sed "s/$/\r/" | base64 -w 0 )
    RECIP=$(get_mails "$MAIL_LIST_REPORT")
    echoout "I:" "gen_for_jira_warn(): get_mails made list: ${RECIP//$'\n'}"
    echo $SUBJJ | jq ". + {recipient: $RECIP, body: \"$BODYB\" }" > $MAILJIRAWARNJSONFILE
    echoout "I;" "gen_for_jira_warn(): generated $MAILJIRAWARNJSONFILE"
    run_command "mv -vf $CI_JOB_NAME.stderr $CI_JOB_NAME-before.$$.stderr"
    RECIPSMTP=$(get_mails "$MAIL_LIST_REPORT" "smtp")
    echoout "I:" "gen_for_mail(): get_mails made list for smtp: ${RECIPSMTP//$'\n'}"
    BODY="$BODYW"
    gen_for_mail_smtp ${MAILJIRAWARNJSONFILE%.json}
else
    echoout "I;" "gen_for_jira_warn(): $JIRACHKRESFILE file not found, maybe no errors in Jira DSO for issue, create empty $MAILJIRAWARNJSONFILE and exit"
    touch $MAILJIRAWARNJSONFILE
    exit 0
fi

}

gen_for_jira_glh() {
ISFAIL="$1"
echoout "I;" "gen_for_jira_glh(): start, arg ^$ISFAIL^ "
if [[ "$ISFAIL" == "failed" ]]; then
    if [[ $STAGE_NAME == "Check_input" || $STAGE_NAME == "Upload" ]]; then
        if grep "Redelivery detected on" $STAGE_NAME.stderr; then
	   echoout "E;" "gen_for_jira_glh(): Not post to JIRA GLH in case of redelivery"
        fi
    elif [[ $STAGE_NAME == "null" ]]; then
         echoout "E;" "gen_for_jira_glh: Cannot find failed stage, called by mistake. stage_name: $STAGE_NAME. return"
         return
    else
         echoout "E;" "gen_for_jira_glh(): got failed stage name $STAGE_NAME"
    fi    
    COMMENT="Delivery checks failed. Providing FixPack $COMMIT stop on stage $STAGE_NAME."
    echoout "I;" "gen_for_jira_glh(): Jira GLH Comment wiil be: $COMMENT"
else
    # prepare readme file with join scope of delivery to end
    add_scope_delivery
    DATE=`date`
    COMMENT="Delivery checks passed. FixPack sent to deployment team on $DATE."
    echoout "I;" "gen_for_jira_glh(): Jira GLH Comment wiil be: $COMMENT + readme file"
    COMMENT=${COMMENT}$(echo; cat $COMMIT.txt )
fi

jq -n --arg body "$COMMENT" '{$body}' > $JIRAGLHJSONFILE
#JSONGLH=$( jq -nc --arg body "$COMMENT" '{$body}' )
#echoout "I;" "gen_for_jira_glh(): gen comment $JSONGLH"
#echo "$JSONGLH" >  $JIRAGLHJSONFILE

}

gen_for_mail_file() {
echoout "I;" "gen_for_mail_file(): start with args \"$*\"" 
MAIL_LIST_REPORT=$1
SUBJ="$2"
SUBJ="[Pipeline $CI_PIPELINE_ID] $COMMIT: $SUBJ"
SUBJJ=`jq -n --arg subj "$SUBJ" '{subject: $subj}'`
INFILE=$3
if [ -f $INFILE ]; then
    cd $CI_PROJECT_DIR
    BODYB=$( cat $INFILE | sed "s/$/\r/" | base64 -w 0 )
    #echo -n $BODY > $INFILE-base64.txt
    RECIP=$(get_mails "$MAIL_LIST_REPORT")
    echoout "I:" "gen_for_mail_file(): get_mails made list: ${RECIP//$'\n'}"
    echoout "I;" "gen_for_mail_file(): Mail subject will be: \"$SUBJ\""
    echoout "I;" "gen_for_mail_file(): Generate mail from file $INFILE to $CI_JOB_NAME.json"
    echo $SUBJJ | jq ". + {recipient: $RECIP, body: \"$BODYB\" }"  > $CI_JOB_NAME.json
    RECIPSMTP=$(get_mails "$MAIL_LIST_REPORT" "smtp")
    echoout "I:" "gen_for_mail(): get_mails made list for smtp: ${RECIPSMTP//$'\n'}"
    BODY=$( cat $INFILE )
    gen_for_mail_smtp $CI_JOB_NAME
else
    echoout "E;" "gen_for_mail_file(): Can not find $INFILE to generate from"
fi
# if subj is text, not json:
#jq -n "{subject: \"$SUBJ\", recipient: $RECIP, body: \"$BODY\" }" > $I---N---FI----LE.json
}

gen_attest_result_file() {

echoout "I;" "gen_attest_result_file(): start" 

if [[ "$P_TESTS" == "true" || "$P_TESTS" == "fail" ]]; then    
    ## cd did not work in run_command
    cd $CI_PROJECT_DIR
    ./scripts/check_atresult.sh
    if [[ -f "$TESTSRESULT" ]]; then
        echoout "I;" "gen_attest_result_file(): File $TESTSRESULT found"
        NUMTESTS=$( cat $TESTSRESULT )
        IFSOLD=$IFS
        IFS='/'
        TEST=($NUMTESTS)
        IFS=$IFSOLD
        echoout "I;" "gen_attest_result_file(): tests result readed ${TEST[0]} / ${TEST[1]}"
        if [[ "$NO_DELIVERY" != "true" ]]; then
            ./scripts/jira-api-search-do.sh updateatcomment ${TEST[0]}  ${TEST[1]}
        else
            echoout "I;" "gen_attest_result_file(): NO_DELIVERY=\"$NO_DELIVERY\" : enabled, do not update comment/upload result"
        fi # if no_delivery
        if [[ "${TEST[0]}" -gt "0" ]]; then
            echoout "E400;" "gen_attest_result_file(): Autotests failed, Amount : ${TEST[0]} / ${TEST[1]}"
            ./scripts/nexus-do.sh nexusupload atresult
            # skip subj redefining at begin of gen_json
            gen_for_mail_file "$MAIL_LIST_REPORT" "Автотесты с ошибкой -  ${TEST[0]} из ${TEST[1]}" failedtests.txt
            echoout "E;" "gen_attest_result_file(): Fail Auto_testing stage by P_TESTS=$P_TESTS and check_atresult = ${TEST[0]} failed "

            exit 1 
        else
            echoout "I110;" "gen_attest_result_file(): Autotests succeeded"
        fi    
    else
        echoout "E404;" "gen_attest_result_file(): Cannot find numtests.txt after check_atresult.sh"
    fi
else
    echoout "E206;" "gen_attest_result_file(): Skipping check_atresult, post comment, upload cucumber.xml, P_TESTS=$P_TESTS"
fi
}

#-------------------- main ---------------------

if [[ "$#" -lt "1" ]]; then
    echo "Too few arguments."
    print_usage
    exit 1
fi

if [[ "$P_PROD_MAIL" != "true" ]]; then
	MAIL_LIST=$DEBUG_MAIL
	ERROR_MAIL_LIST=$DEBUG_MAIL
	MAIL_LIST_REPORT=$DEBUG_MAIL
	MAIL_LIST_ROBOT=$DEBUG_MAIL
fi
echoout "I;" "main(): Start $0 $*"
check_branch

COMMAND="$1"
MAILS="$2"
SUBJ="$3"
FILE="$4"
RES=0

if [ -f $COMHEAD ]; then
# sed {N}p - print N-th line
# if error, then subj will defined later
    if [[ $CI_JOB_NAME != "Error_notification" ]]; then
        SUBJ=$( sed -n 1p $COMHEAD )
    else
        get_job_info "failed"
    fi    
    VENDOR=$( sed -n 2p $COMHEAD | tr "[:lower:]" "[:upper:]" )
    AUTHOR=$( sed -n 3p $COMHEAD )
    JIRA_ID=$( sed -n 4p $COMHEAD )
    RELEASE=$( sed -n 5p $COMHEAD | tr -d ' ')
else
    if [[ -f $COMMIT.txt ]]; then
        SUBJ="[pipeline $CI_PIPELINE_ID / job $CI_JOB_NAME ]: $COMMIT: ошибка разбора файла $COMMIT.txt, отсутствует результат, нет темы"
    else
        SUBJ="[pipeline $CI_PIPELINE_ID / job $CI_JOB_NAME ]: $COMMIT: отсутствует файл readme $COMMIT.txt, нет темы"
    fi    
    VENDOR="не найден"
    AUTHOR="не найден"
    JIRA_ID="не найден"
# do not add excess line in mail, see subj    
#    echoout "E500;" "Do not find file $COMHEAD: Vendor $VENDOR, Author $AUTHOR, JIRA ID $JIRA_ID"
fi
## if author got from cr_contents in check_targz, rewrite it (else it will be empty)
if [ -f author-$COMHEAD ]; then
        AUTHOR=$( sed -n 3p author-$COMHEAD )
fi
echoout "I;" "main(): try get commiter from artifacts $COMMIT-commiter.info"
if [[ -f $COMMIT-commiter.info ]]; then
    COMMITER=$( cat $COMMIT-commiter.info | tr -d '\n')
    echoout "I;" "main(): got commiter from artifact: ^$COMMITER^"
#curl_call "GET"  "noauth" "resp" "nodata" "" "" "$NEXUS_DEVPATH/$COMMIT/$COMMIT-commiter.info"
#if [[ "$CURLCODE" -eq "200" ]]; then
#    COMMITER=$( echo $CURLBODY | tr -d '\n')
#    echoout "I;" "main(): got commiter from nexus: ^$COMMITER^"
else        
    COMMITER="не найден"
    echoout "E;" "main(): cannot find file from artifacts: $COMMIT-commiter.info"
fi 
echoout "I;" "main(): get from $COMHEAD: Vendor $VENDOR, Author $AUTHOR, JIRA ID $JIRA_ID, commiter ^$COMMITER^, release ^$RELEASE^"
echoout "I;" "main(): $COMHEAD: subj $SUBJ"

case "$COMMAND" in
    "genformail" )
    # "mails" arg as robot/not here
        gen_for_mail "$MAILS"
    ;;
    # "mails" arg is failed/success here 
    "genforjiraglh" )
        gen_for_jira_glh "$MAILS"
    ;;
#    "genforjiraglherror" )
#       gen_for_jira_glh_error
#    ;;
    "genformailfile" )
        gen_for_mail_file "$MAILS" "$SUBJ" $FILE
    ;;
    "genforpipelineerrormail" )
        gen_for_pipeline_errormail 
    ;;
    "genforjirawarn" )
		gen_for_jira_warn
    ;;
    "genattestresult" )
        gen_attest_result_file
    ;;
    "genformailerr" )
    # MAILS=errfile in func
        gen_for_mail_err $MAILS
	;;	
    "generrtable" )
	   gen_err_table
    ;;
    "catallstderr" )
    # MAILS=changestatus or not 
	   cat_all_stderr $MAILS
    ;;
    * )
        echo "command not suitable : $COMMAND"
	print_usage
esac
