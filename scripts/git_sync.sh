#!/bin/bash -u

# 24.12.19 Add $GITADDED=1 to not try remove if not added (error before add)
# 26.12.19 change user from zhizhaev@mlh.ru to mlh_ci in gitlab glh
# 26.12.19 remove GIT_SSL_NO_VERIFY=true; use rapid ssl intermediate cert
# 26.12.19 Remove repeated  git config, git remote add, git remote remove; wrote initial setup article
# 14.01.20 add -X theirs merge strategy, see PR-257
# 15.01.20 added funcs: git_init_setup (add remote if absent, no remove), git_get_commits (get git log commit)
# 16.01.10 change check_access from jira api to gitlab api: get user state=active
# 04.03.20 add trap in functions and trap_catch() to send mail about errors. refactor command output to $GITOUT
# 05.03.20 add git reset to same commhash as before pull in trap_catch(), but not when 'already up to date'

## handles many line pulls like:
# * branch                hotfix_new -> FETCH_HEAD
#   a981f1d7c..78e8e2049  hotfix_new -> origin/hotfix_new
# Updating a981f1d7c..78e8e2049
## (line number of 'Updating' unknown)
# and merges like
# * branch                hotfix_new -> FETCH_HEAD
# + 78e8e2049...a5380682d hotfix_new -> origin/hotfix_new  (forced update)
#Merge made by the 'recursive' strategy.
## (no 'Updating' at all)
## and merges like (no 'forced' word)
# * branch                dev_new    -> FETCH_HEAD
#   febae61a5..c3c73ffa0  dev_new    -> origin/dev_new
#Merge made ....
# configure it before first run
## git config --global http.https://gitlab.glh.ru/somebasehost/somebasehost.git.proxy http://10.64.40.155:8080
##git config --global core.autocrlf input
# for initial setup, see http://wiki.corp.dev.mlh/pages/viewpage.action?pageId=36881024

NEXUSPATH=${NEXUSPATH:-"distribs/develop"}
NEXUS_DEV=${NEXUS_DEV:-"http://nexus.corp.dev.mlh/repository/somebase/$NEXUSPATH"}
MAVEN_REPO_USER=${MAVEN_REPO_USER:-"cds"}
MAVEN_REPO_PASS=${MAVEN_REPO_PASS:-"1qazXSW@3edcVFR$"}
COMMITERFILEPATH="/home/ansible/git_sync-log"
MAIL_LIST='"mlh214277@dev.mlh","mlykov@mlh.ru"'
DSOGITUSER="dso-prf-system-ads"
DSOGITPASS="Bipj0jLa"
DSOGITURL="ci.corp.dev.mlh/somebasehost/somebasehost.git"
## for gitlab
DSOGITAPI="http://ci.corp.dev.mlh/api/v4"
CI_PUSH_TOKEN=${CI_PUSH_TOKEN:-"U3hTxJnPszhKZkLgYPxV"}
DSOGITUSERID="210"
## hotfix_new instead hotfix: V. Ismaylov letter at 25.11.2019 11:17
REPOS="hotfix_new dev_new next"
#REPOS="dev_new next"
#REPOS="hotfix_new"
#REPOS="next"
#REPOS="dev_new"
 
trap_catch() {
    local retval=$?
    local line=$1
trap '' ERR EXIT
        echo "trap_catch(): remove git remote repo in case of error (maybe password validity exceeded):  mlh_repo_$repo"
        git remote remove mlh_repo_$repo
	echo "trap_catch(): Error $retval in script. Some error occured, line $line, commit $CHASH, repo $REMREPO, command  ${SCRIPT_T[$line]}. git output : $GITOUT"
	send_notif "git_sync: trap_catch(): Error $retval in script" "$MAIL_LIST" "trap_catch(): Some error occured, exit code $retval, line $line, commit $CHASH, repo $REMREPO, command  ${SCRIPT_T[$line]}. git output : $GITOUT"
	if [[ -n $CURRHASH && -n $repo && $GITPULL -gt 0 ]]; then
	    echo "trap_catch(): reset $repo to $CURRHASH"
	    GITOUT=$( git reset --hard $CURRHASH )
	    echo "$GITOUT"
	else
	    echo "trap_catch: cannot reset, not defined currhash ^$CURRHASH^ or repo ^$repo^ or gitpull not made: ^$GITPULL^"
	fi
exit $retval
}
 
#trap 'trap_catch $LINENO' EXIT
 
 
send_notif() {
SUBJ="$1"
MAIL_LIST="$2"
BODY="$3"
BODY=$( echo -en "\r\n$BODY\r\n" | sed "s/$/\r/" | base64 -w 0 )
JSON_LOAD=$( jq -n "{subject: \"$SUBJ\", recipient:[ $MAIL_LIST ], body: \"$BODY\" }" )
SENDMAILCODE=$( curl -s -w "%{http_code}" -d "$JSON_LOAD"  -H "Content-Type:application/json" -X POST http://10.203.92.186:9080 )
    if [[ "$SENDMAILCODE" -eq "200" ]]; then
        echo "git_sync: send_notif(): error mail sended to $MAIL_LIST"
    else
	echo "git_sync: send_notif(): code $SENDMAILCODE, cannot send error mail to $MAIL_LIST, subject $SUBJ"
    fi
}

git_check_exitcode() {
GITCODE=$1
SUBJ="$2"
MAIL_LIST="$3"
BODY="$4"

if [[ $GITCODE -gt 0 ]]; then
    echo "git_check_exitcode(): Error: $SUBJ ,output: $BODY"
    send_notif "$SUBJ" "$MAIL_LIST" "$BODY"
    echo "git_check_exitcode(): exit with 1 (some error)"
    exit 238
fi
}

git_init_setup() {
trap 'trap_catch $LINENO' ERR
if ! git remote | grep -q "$REMREPO"; then        
    echo "git_init_setup(): not found remote $REMREPO, git remote add it"
    GITOUT=$( git remote add $REMREPO http://$DSOGITUSER:$DSOGITPASS@$DSOGITURL 2>&1 )
    GITREMS=$( git remote | tr '\n' ' ' )
    echo "git_init_setup(): now have remotes: $GITREMS"
fi
}

git_check_access() {
trap 'trap_catch $LINENO' ERR
    GITOUT=$( curl -s -w "%{http_code}" -H "PRIVATE-TOKEN: $CI_PUSH_TOKEN" $DSOGITAPI/users/$DSOGITUSERID )
    GITLABINFO=${GITOUT::-3}
    GITLABCODE=$(echo $GITOUT | tail -c 4)
    if [[ "$GITLABCODE" -ne "200" ]]; then
        echo "git_check_access(): NOT sucessful query Gitlab with private tiken for user $DSOGITUSERID (dso-prf), HTTP status code $GITLABCODE, exit"
    else
	GITLABUSERSTATUS=$( echo $GITLABINFO | jq -r '.state' )
        if [[ "$GITLABUSERSTATUS" != "active" ]]; then
	    echo "git_check_access(): user $DSOGITUSERID (dso-prf) not active, cannot push, exit"
	    git_check_exitcode 1 "git_check_access(): Error in dso-prf user state in gitlab" "$MAIL_LIST" "dso-prf user state in gitlab: $GITLABUSERSTATUS"
	fi    
    fi
}

git_check_push() {
trap 'trap_catch $LINENO' ERR
A_WORDS=( $COMMITS )
echo "git_sync: git_check_push(): check ${#A_WORDS[@]} commit messages, older to newer"
for commit in $COMMITS; do
    GITOPT=""
    CHASH=$( echo $commit | cut -d' ' -f 1 )
    ## commithash-space-commit-mess-spaces@commit author
    CMESS=$( echo $commit | cut -d' ' -f 2- |  cut -d@ -f 1 | cut -d' ' -f 1-8 )
    CCMTER=$( echo $commit | cut -d@ -f 2 )
        if [[  $CMESS =~ ^(\[ci skip\])?.?MLH-(.*) ]]; then
#   	     echo "++++ match -${BASH_REMATCH[1]}- ${BASH_REMATCH[2]}-"
	     MLHMESS=${BASH_REMATCH[2]}
    	    if [[ $MLHMESS =~ ^([0-9]+).* ]]; then
		MLHNUM=${BASH_REMATCH[1]}
    	     	echo "git_sync: good, $CHASH : Push+CI ($CMESS)"
		UPLFILE=MLH-$MLHNUM-commiter.info
		LOCFILE="${COMMITERFILEPATH}/${UPLFILE}"
	        echo "Upload $UPLFILE to nexus $NEXUS_DEV"
	        echo $CCMTER > $LOCFILE
	        CURLCODEOUT=$( curl -v -s -w "%{http_code}" -u $MAVEN_REPO_USER:$MAVEN_REPO_PASS --upload-file $LOCFILE $NEXUS_DEV/MLH-$MLHNUM/$UPLFILE 2>&1 )
#	        CURLCODE=$(echo $CURLCODEOUT | tail -c 4)
	        CURLOUT=${CURLCODEOUT::-3}
	        ## -v gives more output than -I, with '*, >,<'
	        CURLOUT=$(echo "$CURLOUT" |  grep "^<" |  tr '\r\n' '#'| cut -d'#' -f 2-7 )
		echo "Upload nexus responce: $CURLOUT"
            else
		echo "git_sync: bad, $CHASH : Push-CI. MLH-notdigits ($CMESS)"
		GITOPT="-o ci.skip"
	    fi    
        else
	    echo "git_sync: bad, $CHASH : Push-CI. no 'MLH-' at begin ($CMESS)"
	    GITOPT="-o ci.skip"
        fi
    echo "git_sync: start \"git push $GITOPT --force -u $REMREPO $CHASH:$repo\""
    GITOUT=$( git push $GITOPT --force -u $REMREPO $CHASH:$repo 2>&1 )
    echo "$GITOUT" | tail -1
done
}

git_get_commits() {
trap 'trap_catch $LINENO' ERR
	echo "git_get_commits(): start, found Updating|force update|{merge}"
	echo "git_get_commits(): updnum is $UPDNUM, that string: ^${ARRGITPULL[$UPDNUM]}^"
	if [[ ${ARRGITPULL[$UPDNUM]}  =~ ^Updating ]]; then
	   COMMRANGE=$( echo ${ARRGITPULL[$UPDNUM]} | cut -d' ' -f 2 )
	elif [[ ${ARRGITPULL[$UPDNUM]}  =~ ^[[:space:]]\+ ]]; then
	    COMMRANGE=$( echo ${ARRGITPULL[$UPDNUM]} | cut -d' ' -f 3 )
	elif [[ ${ARRGITPULL[$UPDNUM]}  =~ ^[[:space:]]+[a-z0-9]+ ]]; then
	    COMMRANGE=$( echo ${ARRGITPULL[$UPDNUM]} | cut -d' ' -f 4 )
	else
	    git_check_exitcode 1 "git_get_commits(): git pull output parse: no 'Updating/force update/merge' begin" "$MAIL_LIST" "git pull output parse error: $GITPULL"
	fi
	if [[ $COMMRANGE =~ ^[a-z0-9]+\.+[a-z0-9]+ ]]; then
    	    echo "git_get_commits(): got good commrange $COMMRANGE, continue"
	else
	    git_check_exitcode 1 "git_get_commits(): got bad commrange ^$COMMRANGE^" "$MAIL_LIST" "Bad extracted commrange $COMMRANGE. $GITPULL"
	fi
#	COMMITS=$( git log $COMMRANGE --reverse --oneline )
	GITOUT=$( git log $COMMRANGE --reverse --pretty=format:'%h %s @%cn' 2>&1 )
	COMMITS=$GITOUT
	NUMCOMMITS=$( echo "$COMMITS" | wc -l )
	echo "git_get_commits(): got git log strings: $NUMCOMMITS"
	LASTCOMMIT=$( echo $COMMRANGE | tr -s "." " " | cut -d' ' -f 2 )
}


echo "++++----#### $( date ) ####----++++"

#IFS=$'\n' SCRIPT_T=( $(cat "$0"  ) )

readarray -O 1 SCRIPT_T < "$0"

#for elem in $( seq 0 $(( ${#SCRIPT_T[@]} - 1 )) ); do
#    echo -n "$elem: ${SCRIPT_T[$elem]}"
#done
#exit

echo "git_sync: start, check access for user, check remote repo existence"
git_check_access
trap 'trap_catch $LINENO' ERR
for repo in $REPOS; do
    GITPULL=0
    REMREPO="mlh_repo_$repo"
    cd /home/ansible/repos/$repo/somebasehost
    git_init_setup
    echo "git_sync: reset/pull for $repo"
#    GITRESET=$( git reset --hard origin/$repo )
    GITOUT=$( git reset --hard )
    echo "$GITOUT"
    if [[ $GITOUT =~ ^(HEAD is now at )([[:alnum:]]+) ]]; then
#	echo "++++ match -${BASH_REMATCH[1]}- ${BASH_REMATCH[2]}-"
        CURRHASH=${BASH_REMATCH[2]}
#        echo "got currhash $CURRHASH"
    else 
	echo "main(): git reset output did not contain currhash"
    fi
    GITOUT=$( git pull -s recursive -X theirs origin $repo 2>&1  )
    echo "$GITOUT"

    # if not contains up to date - then real gitpull
    if grep -q -v 'Already up to date' <<< $GITOUT; then
	GITPULL=1
    fi
    OLDIFS=$IFS
    IFS=$'\n'
    ARRGITPULL=($GITOUT)
    # -n  = line number -1 for 0-based
    UPDNUM=$( echo "$GITOUT" | grep -v '^$' | grep -nE '(Updating|forced update)' | cut -d: -f 1 )
#'
    let UPDNUM=$UPDNUM-1
    if [[ $UPDNUM -ge 0 ]]; then
	git_get_commits
	    echo "git_sync: call git_check_push(): push as individual push"
	    git_check_push
	echo "git_sync: successful end for $REMREPO"
    elif echo "$GITOUT" | grep -q 'Already up to date'; then
	## without last (head) and first (tail) lines
#	echo "$GITOUT" | head -n -1 | tail -n +2
	echo "git_sync: found \"Already up to date\", nothing to do"
#### grep -q "\- because else '->' as argument: grep: invalid option -- '>'
    elif echo "$GITOUT" | grep -q "\-> origin/$repo"; then
        echo "git_sync: found Non-fastforward merge"
        UPDNUM=$( echo "$GITOUT" | grep -v '^$' | grep -n "\-> origin/$repo"| cut -d: -f 1 )
	let UPDNUM=$UPDNUM-1
	git_get_commits
        git_check_push
	echo "git_sync: successful end for $REMREPO"
    else
	echo -e "Cannot find any of Updating/force update/Already up to date/non-fastforward merge in output:\n $GITOUT"
	send_notif "git_sync: Error : Cannot find any of Updating/force update/Already up to date/non-fastforward merge" "$MAIL_LIST" "Cannot find any of Updating/force update/Already up to date/non-fastforward merge in ouptut: $( echo "$GITOUT" | sed "s/$/\r/") "
    fi
done
