#!/bin/bash

CURDIR=$(pwd)
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_NAME=${CI_JOB_NAME:-"checkafterinstall"}
P_DEPLOY=${P_DEPLOY:-"true"}
P_DEPLOY_CHECK=${P_DEPLOY_CHECK:-"true"}
CI_PIPELINE_ID=${CI_PIPELINE_ID:-"77443"}
COMMIT=${COMMIT:-"MLH-7788"}
DEPLOYRESFILE=${DEPLOYRESFILE:-"deploy_result-$COMMIT.txt"}
DEPLOYCHECKERRFILE=${DEPLOYCHECKERRFILE:-"check-notok.txt"}

source ./scripts/common_func.sh

echoout "I;" "main(): Start $0 with arguments $*"
check_branch
echoout "I;" "P_DEPLOY $P_DEPLOY  P_DEPLOY_CHECK $P_DEPLOY_CHECK"
LSDIR=$(ls install_logs_$COMMIT_*.zip)
echoout "I;" "current install logs: $LSDIR"

if [[ "$P_DEPLOY" == "true" ]]; then
    cp -v $CI_PROJECT_DIR/scripts/log.conf $CI_PROJECT_DIR
    for INSTLOG in $LSDIR; do
        if [[ $INSTLOG =~ logs_${COMMIT}_([[:digit:]]+).zip$ ]]; then
            SERVNUM=${BASH_REMATCH[1]}
            echoout "I;" "main(): unpack log archive from server $SERVNUM"
        else
            echoout "E;" "main(): log name $INSTLOG did not contain server number"
        fi
        ## -j unpack in current dir; -o overwrite if exist without query
        run_command "unzip -jo $INSTLOG"
        ./scripts/CheckLog.py
        if [ -f check.txt ]; then
            cat check.txt
            if [[ "$P_DEPLOY_CHECK" == "true" ]]; then
                ERRCH=$(grep 'ERROR' check.txt)
                GREX=$?
                if [[ "$GREX" -eq "0" ]]; then
                    if grep 'ERROR.*Files not found' check.txt; then
                        echoout "E300;" "ERROR in check.txt - log files not found!"
                        exit 1
                    fi
                    echoout "E301;" "ERROR word found in check results"
                    echoout "E;" "Adding  check.txt contents to $DEPLOYCHECKERRFILE for server $SERVNUM"
                    echo "Check result from server $SERVNUM:" >> $DEPLOYCHECKERRFILE
                    cat check.txt >> $DEPLOYCHECKERRFILE
                    COMMENT=$(printf "%s\n%s" "ERROR: $INSTLOG: лог установки (повторяющиеся ошибки находятся в разных строках исходного файла):" "$ERRCH")
                    if [[ "$NO_DELIVERY" != "true" ]]; then
                        ./scripts/jira-api-search-do.sh postcomment "$COMMENT"
                    else
                        echoout "I;" "NO_DELIVERY=\"$NO_DELIVERY\" : enabled, do not post comment errors in checkatresult"
                    fi # if no_delivery
                    if [ -f $DEPLOYRESFILE ]; then
                        while read FULLDEPRES; do
                            RESULT=$(echo "$FULLDEPRES" | awk -F- {'print $4'})
                            if [[ "$RESULT" == "deploy SUCCESS" ]]; then
                                HOBABR=$(echo "$FULLDEPRES" | awk -F- {'print $1"-"$2"-"$3'})
                                RESULT="deploy FAIL"
                                echoout "E;" "writing updated ${HOBABR}-${RESULT} to $DEPLOYRESFILE"
                                echo ${HOBABR}-${RESULT} >$DEPLOYRESFILE
                            else
                                echoout "E;" "deploy result already: $RESULT"
                            fi
                        done <$DEPLOYRESFILE
                        echoout "E;" "update result table with updated FAIL result, res file $DEPLOYRESFILE"
                        ./scripts/jira-api-search-do.sh updateresulttable $DEPLOYRESFILE
                    fi
                    ## after e301 and postcomment
                    exit 1
                elif [[ "$GREX" -eq "1" ]]; then
                    echoout "I109;" "no ERRORs found in check log"
                    #            	        echoout "I;" "$(cat check.txt)"
                    echoout "I;" "update result table because success, result file $DEPLOYRESFILE"
                    if [[ "$NO_DELIVERY" != "true" ]]; then
                        ./scripts/jira-api-search-do.sh postcomment "$INSTLOG: Установка успешна, в логе ошибок нет [pipeline $CI_PIPELINE_ID]"
                    else
                        echoout "I;" "NO_DELIVERY=\"$NO_DELIVERY\" : enabled, do not post success result in checkatresult"
                    fi # if no_delivery
                fi     # if error
                ERWCH=$(grep 'WARNING' check.txt)
                GREX=$?
                if [[ "$GREX" -eq "0" ]]; then
                    echoout "E304;" "WARNING word found in check results"
                fi

            # if p_deploy_check
            else
                echoout "I;" "DEPLOY_CHECK disabled (no need to check logs)"
                echo "check-disabled-VAR-$P_DEPLOY_CHECK" >deploy_result-$COMMIT.txt
                echoout "I;" "update result table with 'disabled' result, res file $DEPLOYRESFILE"
                echoout "I;" "post comment about result = 'disabled'"
                if [[ "$NO_DELIVERY" != "true" ]]; then
                    ./scripts/jira-api-search-do.sh postcomment "$INSTLOG: Установка не проверялась на ошибки в логе установки, потому что P_DEPLOY_CHECK-$P_DEPLOY_CHECK, установил $GITLAB_USER_NAME"
                else
                    echoout "I;" "NO_DELIVERY=\"$NO_DELIVERY\" : enabled, do not post about 'not checked deploy result' in checkatresult"
                fi # if no_delivery
            fi     # if p_deploy_check
        # if -f check.txt
        else
            echoout "E302;" "not found check.txt log after CheckLog.py!"
        fi
    done # install logs
    ./scripts/jira-api-search-do.sh updateresulttable $DEPLOYRESFILE
else
    echoout "I;" "DEPLOY disabled (no logs to check)"
fi
