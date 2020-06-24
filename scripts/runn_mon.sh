#!/bin/bash

# ver 2: add early exits, remove unneeded log output, change save file only if new off. run appear
# ver 3: add consecutive offline counts for every runner; mail warn only every 'divider' count
# ver 4: refactor to add_list, delete_list for save file instead compare num of loaded/current
# ver 5: fix correct load/reset/save cycle

## max api got runners simultaneously to start check
RUNNLIMIT=2
## max consequently cycles to stay runner offline before notify
RUNNCOUNTLIMIT=4
## mail warning if max of runners count divided without module 
RUNNCOUNTDIVIDER=24
SAVERUNSTFILE="runn_mon/runner.status"
#SAVERUNSTFILE="runner.status"
MAILSERVER="http://10.203.92.186:9080"
MAIL_LIST='"mlh214277@dev.mlh","mlykov@mlh.ru"'
GITLABHOST="http://ci.corp.dev.mlh"
GITLABURL="/api/v4/projects/190/runners?tag_list=rhel;status=offline"

DSOGITAPI="http://ci.corp.dev.mlh/api/v4"
CI_PUSH_TOKEN=${CI_PUSH_TOKEN:-"U3hTxJnPszhKZkLgYPxV"}
DSOGITPROJID="190"
DSORUNTAGLIST="rhel"
DSORUNSTATUS="offline"

## RUNNSTATUS - hash: got all keys from gitlab json for api query (on+off)
declare -A RUNNSTATUS
## ROFFLCOUNT = hash : loaded key-value from file
declare -A ROFFLCOUNT
## RUNNOFFLINE - hash: got only online:false keys from gitlab json
declare -A RUNNOFFLINE
## RUNNSTLOAD = array of keys in ROFFLCOUNT
declare -a RUNNSTLOAD

send_notif() {
SUBJ="$1"
MAIL_LIST="$2"
BODY="$3"
BODY=$( echo -en "\r\n$BODY\r\n" | sed "s/$/\r/" | base64 -w 0 )
JSON_LOAD=$( jq -n "{subject: \"$SUBJ\", recipient:[ $MAIL_LIST ], body: \"$BODY\" }" )
SENDMAILCODE=$(curl -s -w "%{http_code}" -d "$JSON_LOAD"  -H "Content-Type:application/json" -X POST $MAILSERVER )
    if [[ "$SENDMAILCODE" -eq "200" ]]; then
        echo "send_notif(): error mail sended to $MAIL_LIST"
    fi
}

load_runners() {
#    echo "load_runners(): start" 
    touch $SAVERUNSTFILE
    while IFS=: read -r key value; do
	if [[ -n $key ]]; then
#    	    echo "key ^$key^ value ^$value^"
    	    ROFFLCOUNT[$key]=$value
	fi
    done < "$SAVERUNSTFILE"
#    echo "keys ^${!ROFFLCOUNT[*]}^ values ^${ROFFLCOUNT[*]}^"
    RUNNSTLOAD=( $( printf "%s\n"  ${!ROFFLCOUNT[*]} | sort ) )
#    printf "load_runners(): loaded was offline: %s\n" ${RUNNSTLOAD[*]} 
    NUMLOADED=${#RUNNSTLOAD[*]}
    echo "load_runners(): loaded $NUMLOADED: ^${RUNNSTLOAD[*]}^"
#    return $NUMLOADED
#    exit
}

save_runners() {
    MAXRUNNCOUNT=0
    SAVEDCOUNT=0
    MAXRUNN=""
    SAVEVARS=""
    echo "save_runners(): all counted ^${!ROFFLCOUNT[*]}^  " 
    touch $SAVERUNSTFILE
    for i in ${!ROFFLCOUNT[*]}; do
#        echo "s1: key $i value ${ROFFLCOUNT[$i]}"
#	echo "save_runners(): save $i:${ROFFLCOUNT[$i]}"
        if [[ ${ROFFLCOUNT[$i]} -eq 0 ]]; then
            echo "save_runners(): skip $i because it resetted to 0"
            continue
        else
            printf -v SAVEVAR "%s\n" "$i:${ROFFLCOUNT[$i]}"
            SAVEVARS=${SAVEVARS}${SAVEVAR}
            let SAVECOUNT=SAVECOUNT+1
        fi
        if [[ ${ROFFLCOUNT[$i]} -gt $MAXRUNNCOUNT ]]; then
            MAXRUNNCOUNT=${ROFFLCOUNT[$i]}
            MAXRUNN="$i"
        fi
#        echo "savevar ^$SAVEVAR^ "
#        SAVEVAR=${SAVEVAR}$(echo  "$i:${ROFFLCOUNT[$i]}" )
#        SAVEVAR=${SAVEVAR}$(printf "%s\n" "$i:${ROFFLCOUNT[$i]}" )
#        echo "$SAVEVARS"

    done
    echo "save_runners(): save $SAVECOUNT offline runners, max cycles $MAXRUNNCOUNT for $MAXRUNN"
    echo "$SAVEVARS" >  $SAVERUNSTFILE
}

delete_runners_list() {
    echo "delete_runners_list(): loaded offline: ${!ROFFLCOUNT[*]}"
#    echo ${RUNNOFFLCURR[*]}

    for i in "${RUNNSTLOAD[@]}"
    do
#        echo i ^$i^
#	echo offline ${RUNNOFFLINE[$i]}
	## bash  param substitition/rarameter expansion like {VAR:-value}
	## if first part is unset, then all is null. if it is not unset, then all is second par.
#	echo "exist curr ^${RUNNOFFLCURR[$i]+isset}^"
	if [[ ${RUNNOFFLINE[$i]+isset} ]]; then
    	    echo "delete_runners_list(): $i still offline now, continue"
	else
	    ROFFLCOUNT[$i]="0"
	    echo "delete_runners_list(): $i is no more offline, set count to 0"
	fi
#    if [[ $NUMLOADED -gt $NUMCURR ]]; then
#        echo "compare_runners_numbers(): loaded strings > current strings, clear save file, exit"
#        echo "" > $SAVERUNSTFILE
#        RUNNSTLOAD=()
#	exit
#    fi
    done
}    

add_runners_list() {
    echo "add_runners_list(): curent offline: ${!RUNNOFFLINE[*]} "
    j=0
    NOTIF=0
    NOTIFRUNN=""
    for i in "${!RUNNOFFLINE[@]}"
    do
#        echo "step: $j, curr1  : $i"
#        echo "load2: ${RUNNSTLOAD[$j]}"
        if [[ -n ${ROFFLCOUNT[$i]} && ${ROFFLCOUNT[$i]} -gt 0 ]]; then
#        if [[ "$i" == "${RUNNSTLOAD[$j]}" ]]; then
	    let ROFFLCOUNT[$i]=ROFFLCOUNT[$i]+1
            echo "add_runners_list(): runner $i already in save file, now : ${ROFFLCOUNT[$i]} "
            if [[ ${ROFFLCOUNT[$i]} -ge $RUNNCOUNTLIMIT ]]; then
                NOTIF=2
            fi
#            # next load only if it already found
#            let j=j+1
        else 
            echo "add_runners_list(): runner $i new or resetted, save it in file with 1"
            ROFFLCOUNT[$i]="1"
#            NOTIFRUNN=${NOTIFRUNN}$(echo -e "\n$i")
            NOTIF=1
            #add new runner to array to save
#            RUNNSTLOAD[${#RUNNSTLOAD[*]}]="$i"
       fi
#        echo " rofflcount ^$i^ ^${ROFFLCOUNT[$i]}^"
    done
#    echo "compare_runners_list(): save ${#RUNNSTLOAD[*]} runners to save file"
#    printf "%s\n" ${RUNNSTLOAD[*]} > $SAVERUNSTFILE
#    if [[ $j -gt 0 || $NOTIF -gt 0 ]]; then
	save_runners
#    fi	
}

get_curr_runners() {
#    echo "get_curr_runners(): start, query Gitlab Runners API" 
    # jq  -r '.[] | length' got key-value hash  number of elements (8), not array elements (2), wc -l count number of strings with count key-value hash elements

    GITLABINFOCODE=$( curl -s -w "%{http_code}" -H "PRIVATE-TOKEN: $CI_PUSH_TOKEN" "$DSOGITAPI/projects/$DSOGITPROJID/runners?tag_list=$DSORUNTAGLIST;status=$DSORUNSTATUS" )
    GITLABINFO=${GITLABINFOCODE::-3}
    GITLABCODE=$(echo $GITLABINFOCODE | tail -c 4)
    if [[ "$GITLABCODE" -ne "200" ]]; then
        echo "git_curr_runners(): can NOT query Gitlab: $DSOGITAPI/projects/$DSOGITPROJID/runners?tag_list=$DSORUNTAGLIST;status=$DSORUNSTATUS : HTTP status code $GITLABCODE, exit"
        exit 1
    fi
#    GITLABINFO=$( cat runn.json )
    NUMRUNNS=$( echo $GITLABINFO | jq -r '.[] | length' | wc -l )
    echo "get_curr_runners(): got $NUMRUNNS runners in responce; continue if >= $RUNNLIMIT"
    if [[ "$NUMRUNNS" -ge $RUNNLIMIT ]]; then
#        echo "get_curr_runners(): runners count >= $RUNNLIMIT"
        while read -r host status; do
            if [ -n "$host" ]; then 
                # remove spaces from keys, if any
                host=${host// /}
                RUNNSTATUS[$host]="$status"
                echo "get_curr_runners(): got runner $host online status $status"
            fi
        done < <( echo $GITLABINFO | jq -r '.[] | .description,.online' )
    # ! is an array key
        for i in "${!RUNNSTATUS[@]}"; do
            if [[ ${RUNNSTATUS[$i]} == "false" ]]; then
                RUNNOFFLINE[$i]="yes"
#                echo "get_curr_runners(): add runner $i to offline runners list"
            fi
        done
    fi
    RUNNOFFLCURR=( $( printf "%s\n" ${!RUNNOFFLINE[*]}| sort ) )
#    printf "get_curr_runners(): current offline: %s\n" ${RUNNOFFLCURR[*]} 
    NUMCURR=${#RUNNOFFLCURR[*]}
    if [[ $NUMCURR -eq 0 ]]; then
	echo "get_curr_runners(): current offline $NUMCURR, exit"
	delete_runners_list
	save_runners
	exit
    fi
#    return $NUMLOADED
}


#----------- main ----------------

echo "++++----#### $( date ) ####----++++"

load_runners
get_curr_runners
delete_runners_list
add_runners_list

if [[ $NOTIF -gt 1 ]]; then
    echo "runn_mon.sh: $MAXRUNN runner offline count $MAXRUNNCOUNT >  limit $RUNNCOUNTLIMIT, divider $RUNNCOUNTDIVIDER "
#    printf "%s\n" ${RUNNSTLOAD[*]} > $SAVERUNSTFILE
    let "mod = MAXRUNNCOUNT % $RUNNCOUNTDIVIDER"
    if [[ $mod -eq 0 ]]; then
        echo "runn_mon.sh: send warn email because $MAXRUNNCOUNT divided by $RUNNCOUNTDIVIDER (next step passed)"
        send_notif "runn_mon.sh: $MAXRUNN runner offline count $MAXRUNNCOUNT >  limit $RUNNCOUNTLIMIT cycles" "$MAIL_LIST" "$SAVEVARS"
    fi
fi