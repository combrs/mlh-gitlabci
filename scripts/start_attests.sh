#!/bin/bash

CURDIR=`pwd`
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_NAME=${CI_JOB_NAME:-"ATtest"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}
COMMIT=${COMMIT:-"MLH-7788"}
AT_GR=${AT_GR:-"ci.corp.dev.mlh/AutoTest"}
AT_PROJECT=${AT_PROJECT:-"Somebase_tests"}
ATREPORT="$CI_PROJECT_DIR/Temp/$AT_PROJECT/target"
TESTSRESULT=${TESTSRESULT:-"numtests.txt"}
BUILD_USER=${BUILD_USER:-"dso-prf-system-ads"}
USER_TOKEN=${USER_TOKEN:-"U3hTxJnPszhKZkLgYPxV"}
URL="http://$BUILD_USER:$USER_TOKEN@$AT_GR/$AT_PROJECT.git"
P_TESTS=${P_TESTS:-"true"}
BRANCH=${BRANCH:-"hotfix"}

source ./scripts/common_func.sh

get_autotest_git() {
    echoout "I;" "get_autotest_git(): start"
    # Забираем проект из git
    run_command "git config user.name $BUILD_USER"
    run_command "git config user.email \"noreply@mlh.ru\""
    run_command "mkdir -vp $CI_PROJECT_DIR/Temp/"
    ## cd failed to run in run_command: exit code 0, but not change dir
    cd $CI_PROJECT_DIR/Temp/
    run_command "git clone $URL"
    cd $CI_PROJECT_DIR/Temp/$AT_PROJECT
    run_command "git checkout $BRANCH"
}

echoout "I;" "start; current dir : $CURDIR"
check_branch
## old code, copied from somebasehost gitlab-ci ?
#rm -rf ~/st/git || /bin/true
echoout "I;" "remove previous $AT_PROJECT dir to avoid git clone failure "
#### ./scripts/start_attests.sh fatal: destination path 'Somebase_tests' already exists and is not an empty directory.
run_command "rm -vrf $CI_PROJECT_DIR/Temp/$AT_PROJECT || /bin/true"

# cut dev{_anything} from somebasehost to 'dev' in somebase_tests, branch in somebasehost may be renamed
BRANCH=$(echo $BRANCH | cut -d_ -f 1)

echoout "I;" "start autotests clone git  for branch $BRANCH supply $COMMIT "
TESTTAG="@test_smoke_new"
[[ "$P_TESTS" == "schedule" ]] && TESTTAG="@test_xml"

echoout "I;" "if tests enabled .. P_TESTS $P_TESTS ... then test with $TESTTAG"
if [[ $P_TESTS == "true" || $P_TESTS == "schedule" ]]; then 
        get_autotest_git  
        echoout "I;" "current dir `pwd`"
        echoout "I;" "start maven test autotests for branch $BRANCH supply $COMMIT "
        echoout "I;" "run /opt/apache-maven-3.6.0/bin/mvn test -Dcucumber.options=\"--tags @test_smoke_new\" -s src/settings/settings.xml -P Nexus -Denv=$BRANCH"
        /opt/apache-maven-3.6.0/bin/mvn test -Dcucumber.options="--tags $TESTTAG" -s src/settings/settings.xml -P Nexus -Denv=$BRANCH
        MVNTESTEXCODE=$?
        echoout "I;" "mvn test exit code is $MVNTESTEXCODE"
        run_command "cp -v testrun_log.log $CI_PROJECT_DIR"
        run_command "cp -v cucumber.xml $CI_PROJECT_DIR"
        /opt/apache-maven-3.6.0/bin/mvn allure:report -s src/settings/settings.xml -P Nexus -q
elif [[ "$P_TESTS" == "fail" ]]; then
        get_autotest_git
     echoout "I;" "P_TESTS=$P_TESTS, copy file with failed results in place of real file"
     run_command "mkdir -vp $ATREPORT/site/allure-maven-plugin/data/"
     run_command "cp -v $ATREPORT/allure-results/packages-failed2.json $ATREPORT/site/allure-maven-plugin/data/packages.json"
else        
         echoout "I;" "Skipping git clone/tests/reports because tests disabled, P_TESTS=$P_TESTS"
         exit 0
fi

