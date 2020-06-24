#!/bin/bash

CURDIR=$(pwd)
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
AT_PROJECT=${AT_PROJECT:-"Somebase_tests"}
ATREPORT="$CI_PROJECT_DIR/Temp/$AT_PROJECT/target/site/allure-maven-plugin"
CI_PIPELINE_ID=${CI_PIPELINE_ID:-"66554"}
CI_JOB_NAME=${CI_JOB_NAME:-"check-atresult"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}
TESTSRESULT=${TESTSRESULT:-"numtests.txt"}

source ./scripts/common_func.sh
echoout "I;" "main(): Start $0 with arguments $*"

if [ -f "$ATREPORT/data/packages.json" ]; then

    PJ="$ATREPORT/data/packages.json"
    NUMCHILDS=$(jq '.children | length' "$PJ")
    ALLTESTS=$(jq '.statistic.total' "$PJ")
    NUMPASSED=$(jq '.statistic.passed' "$PJ")
    NUMFAILED=$(jq '.statistic.failed' "$PJ")
    NUMBROKEN=$(jq '.statistic.broken' "$PJ")
    NUMUNKN=$(jq '.statistic.unknown' "$PJ")
    echoout "I;" "NUMCHILDS=$NUMCHILDS ALLTESTS=$ALLTESTS NUMPASSED=$NUMPASSED NUMFAILED=$NUMFAILED NUMBROKEN=$NUMBROKEN NUMUNKN=$NUMUNKN"    
    for ((num=0; num <NUMCHILDS; num++)); do
      CHILDNUM=$(jq -r .children[$num].statistic.total "$PJ")
    	for ((num2=0; num2 <CHILDNUM; num2++)); do
    		    STATUS=$(jq -r .children[$num].children[$num2].status "$PJ")
       		    if [[ "$STATUS" == "passed" ]]; then
                		PASSN1=$(jq -r .children[$num].name "$PJ")
        			PASSN2=$(jq -r .children[$num].children[$num2].name "$PJ")
        			PASSN=${PASSN1//$'\n'/}" / ${PASSN2}"
        			PASSNAME[${#PASSNAME[@]}]="$PASSN"
        		fi
       		    if [[ "$STATUS" == "failed" ]]; then
                		FAILN1=$(jq -r .children[$num].name "$PJ")
        			FAILN2=$(jq -r .children[$num].children[$num2].name "$PJ")
        			FAILN=${FAILN1//$'\n'/}" / ${FAILN2}"
        			FAILNAME[${#FAILNAME[@]}]="$FAILN"
        		fi
       		    if [[ "$STATUS" == "broken" ]]; then
                		FAILN1=$(jq -r .children[$num].name "$PJ")
        			FAILN2=$(jq -r .children[$num].children[$num2].name "$PJ")
        			FAILN=${FAILN1//$'\n'/}" / ${FAILN2}"
        			BROKENNAME[${#BROKENNAME[@]}]="$FAILN"
    	#		    echo ffff ${FAILNAME[$num]}
        		fi
       		    if [[ "$STATUS" == "unknown" ]]; then
                		FAILN1=$(jq -r .children[$num].name "$PJ")
        			FAILN2=$(jq -r .children[$num].children[$num2].name "$PJ")
        			FAILN=${FAILN1//$'\n'/}" / ${FAILN2}"
        			UNKNNAME[${#UNKNNAME[@]}]="$FAILN"
    	#		    echo ffff ${FAILNAME[$num]}
        		fi
        done
    done


    if [[ "$NUMCHILDS" -gt "0" ]]; then
    	PASSARR=${#PASSNAME[@]}
    	FAILARR=${#FAILNAME[@]}
    	BROKENARR=${#BROKENNAME[@]}
    	UNKNARR=${#UNKNNAME[@]}
    	ARRALLSUM=$(( PASSARR+FAILARR+BROKENARR+UNKNARR ))
    	ALLSUM=$(( NUMPASSED+NUMFAILED+NUMBROKEN+NUMUNKN ))
    	ARRALLFAILED=$(( FAILARR+BROKENARR ))
    	if [[ "$ALLTESTS" -ne "$ALLSUM" ]]; then
    	    echoout "E;" "WRONG result: 'total' statistic result:$ALLTESTS not comply 'passed+failed+broken+unknown' statistic result:$ALLSUM"
    	fi
    	if [[ "$PASSARR" -ne "$NUMPASSED" || "$FAILARR" -ne "$NUMFAILED" || "$BROKENARR" -ne "$NUMBROKEN" || "$UNKNARR" -ne "$NUMUNKN" ]]; then
    	    echoout "E;" "WRONG result: 'passed,failed,broken,unknown' children counted result:$PASSARR,$FAILARR,$BROKENARR,$UNKNARR not comply 'passed,failed,broken,unknown' statistic result:$NUMPASSED,$NUMFAILED,$NUMBROKEN,$NUMUNKN"
    	    echoout "E;" "result in failedtests is children counted" 
    	fi
            if [[ "$ARRALLFAILED" -gt "0" ]]; then
    #	        echo zzz ${FAILNAME[@]}
        	    FAILEDTEST=$(printf '%s\n' "${FAILNAME[@]}")
        	    BROKENTEST=$(printf '%s\n' "${BROKENNAME[@]}")
        	    UNKNTEST=$(printf '%s\n' "${UNKNNAME[@]}")
                echoout "E;" "FAILED Tests: $FAILARR, broken: $BROKENARR, see failedtests.txt"
    	        [ "$FAILARR" -gt 0 ] && echo "Список проваленных тестов  : $FAILARR" > failedtests.txt && echo "$FAILEDTEST" >> failedtests.txt
        	    [ "$BROKENARR" -gt 0 ] && echo "Список сломанных тестов  : $BROKENARR" >> failedtests.txt && echo "$BROKENTEST" >> failedtests.txt
            else
                echoout "I;" "Pipeline $CI_PIPELINE_ID: PASSED $PASSARR, broken $BROKENARR, unknown $UNKNARR, ALL $ARRALLSUM"
            fi
    	    [ "$UNKNARR" -gt 0 ] && echo "Список неизвестного состояния тестов : $UNKNARR " >> failedtests.txt && echo "$UNKNTEST" >> failedtests.txt
    	    echoout "I;" "Save result $FAILARR/$ARRALLSUM to file $TESTSRESULT"
    	    echo "$ARRALLFAILED/$ARRALLSUM" > $CI_PROJECT_DIR/$TESTSRESULT
    else
        echoout "E;" "Did not do any tests, number of tests in first [children] is $NUMCHILDS"
        exit 0
    fi
else
        echoout "E;" "NOT found autotests result file $ATREPORT/data/packages.json"
        exit 0
fi
