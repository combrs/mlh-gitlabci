#!/usr/bin/bash

CURDIR=`pwd`
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_NAME=${CI_JOB_NAME:-"ATtest"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}

AT_GR=${AT_GR:-"ci.corp.dev.mlh/AutoTest"}
AT_PROJECT=${AT_PROJECT:-"Somebase_tests"}
BUILD_USER=${BUILD_USER:-"dso-prf-system-ads"}
USER_TOKEN=${USER_TOKEN:-"U3hTxJnPszhKZkLgYPxV"}
URL="http://$BUILD_USER:$USER_TOKEN@$AT_GR/$AT_PROJECT.git"
MAIL_LIST_REPORT=${MAIL_LIST_REPORT:-"mlykov@mlh.ru, mlh214277@dev.mlh"}
MAVEN_REPO_USER=${MAVEN_REPO_USER:-"cds"}
MAVEN_REPO_PASS=${MAVEN_REPO_PASS:-"1qazXSW@3edcVFR$"}

source ./scripts/common_func.sh
if [[ "$P_TESTS" == "true" ]]; then    
    cd $CI_PROJECT_DIR/Temp/$AT_PROJECT
    run_command "cp -v testrun_log.log $CI_PROJECT_DIR"
    run_command "cp -v cucumber.xml $CI_PROJECT_DIR"
    /opt/apache-maven-3.6.0/bin/mvn allure:report -s src/settings/settings.xml -P Nexus -q
fi    
## cd did not work in run_command
cd $CI_PROJECT_DIR
./scripts/check_atresult.sh
#if grep -i "E;" $CI_JOB_NAME.stderr>/dev/null ; then
if [ -f numtests.txt ]; then
    NUMTESTS=`cat numtests.txt`
    IFS='/'
    TEST=($NUMTESTS)
    if [[ "${TEST[0]}" -gt "0" ]]; then
	     echoout "E400;" "Autotests failed, Amount : ${TEST[0]} / ${TEST[1]}"
        ./scripts/gen_json_from_readme.sh genformailfile "$MAIL_LIST_REPORT" "Автотесты с ошибкой - $NUMTESTS" failedtests.txt
        ./scripts/jira-api-search-do.sh updateatcomment 
        echoout "E;" "Fail Auto_testing stage"
        exit 1    
    fi
else
    echoout "E404;" "Cannot find numtests.txt after check_atresult.sh"
fi

