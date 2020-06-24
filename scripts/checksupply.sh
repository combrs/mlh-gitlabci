#!/bin/bash

set -o pipefail

CURDIR=$(pwd)
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_NAME=${CI_JOB_NAME:-"Upload"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}
ISSTYPES=${ISSTYPES:-"OS- BR- TST- IMPL-"}
COMMIT=${COMMIT:-"MLH-8888"}
URL="/release/$COMMIT/ST_$COMMIT.zip"
BRANCH=${BRANCH:-"next"}
COMHEAD=${COMHEAD:-"commheader.txt"}
CPAGECHKFILE=${CPAGECHKFILE:-"cpagechk.txt"}
RESDIFFFILE=${RESDIFFFILE:-"resdiffsha1.txt"}
P_CHECK_ENC=${P_CHECK_ENC:-"true"}
P_CHECK_ANSBRANCH=${P_CHECK_ANSBRANCH:-"true"}
P_CHECK_REDELIVERY=${P_CHECK_REDELIVERY:-"true"}
PFHOST_BR_TOKEN=${PFHOST_BR_TOKEN:-"sxzKdBEo2bCzZgTZT_Zb"}
PFHOSTNAME=${PFHOSTNAME:-"somebasehost"}
PFHOSTURL=${PFHOSTURL:-"http://somebaseci-git:$PFHOST_BR_TOKEN@ci.corp.dev.mlh/$PFHOSTNAME/$PFHOSTNAME.git"}
NEXUS_URL=${NEXUS_URL:-"http://nexus.corp.dev.mlh"}
NEXUS_DEV=${NEXUS_DEV:-"develop"}
NEXUS_REL=${NEXUS_REL:-"release"}
NEXUSRESFILE=${NEXUSRESFILE:-"nexussearchres.json"}
NEXUS_USER=${NEXUS_USER:-"cds"}
NEXUS_PASS=${NEXUS_PASS:-"1qazXSW@3edcVFR$"}

NEXUS_AUTH=$(echo -n $NEXUS_USER:$NEXUS_PASS | base64)
NEXUS_REMOVEPATH="distribs/${NEXUS_DEV}/${COMMIT}/"
NEXUS_DEVPATH="${NEXUS_URL}/repository/somebase/distribs/${NEXUS_DEV}"
NEXUS_RELPATH="${NEXUS_URL}/repository/somebase/distribs/${NEXUS_REL}"

source ./scripts/common_func.sh

print_usage() {
    echoout "     Usage:
#              $PROG readmeexist  - check readme file presence for MLH-XXXX (MLH-XXXX.txt)
#              $PROG distribexist  - check supply file presence for MLH-XXXX (ST_MLH-XXXX.zip)
              $PROG nexusexist {readme}  - check readme file presence for MLH-XXXX (MLH-XXXX.txt)
              $PROG nexusexist {distrib} - check supply file presence for MLH-XXXX (ST_MLH-XXXX.zip)
              $PROG nexusexist {targz} - check targz file presence for MLH-XXXX (ST_MLH-XXXX.tar.gz)
              $PROG hostexist  - check ansible inventory for supplied host/group '$BRANCH'
              $PROG checkcommit  - check supply name format for MLH-[digits]
              $PROG checkjiraids  - check given jira id(s) matching with given prefix list   
              $PROG checksupplytargz  - unpack and check targz for author/codepage/etc
              $PROG checkdatajson  - check generated data.json values to be equal supply values
          "
}

check_commit() {

    echoout "I;" "check_commit(): start, will check format of this: $COMMIT. MUST be 'MLH-[digits]'"
    if [[ $COMMIT =~ ^MLH-(.*) ]]; then
        if [[ ! ${BASH_REMATCH[1]} =~ ^[0-9]+$ ]]; then
            echoout "E190;" "check_commit(): part afer '-' contain non-digits: $COMMIT"
            exit 1
        fi
    else
        echoout "E191;" "check_commit(): commit not begin from 'MLH-'. Not allowed supply name : $COMMIT"
        exit 1
    fi
    echoout "I101;" "check_commit(): $COMMIT format correct"
}

check_dependencies() {
    if [[ $NO_CHECK_DEPS == "true" ]]; then
        echoout "I;" "check_dependencies(): NO_CHECK_DEPS $NO_CHECK_DEPS, return"
        return
    fi
    echoout "I;" "check_dependencies(): start"
    if [[ -f $COMMIT.txt ]]; then
        echoout "I;" "check_dependencies(): found $COMMIT.txt, grep non-format dependencies"
        DEPLINENUM=$(grep -n 'Dependencies:' $COMMIT.txt | cut -d: -f 1)
        # skip "---------"
        DEPMLH=$((DEPLINENUM + 2))
        echoout "I;" "check_dependencies(): found 'MLH-' dependencies start at line $DEPMLH, check below it"
        DEPMLHTAIL=$(tail -n +$DEPMLH $COMMIT.txt)
        DEPMLHNONFORMAT=$(echo "$DEPMLHTAIL" | grep -E '^MLH' | grep -vE '^MLH-[0-9]{3,5}[[:space:]]+?$')
        if [[ -n $DEPMLHNONFORMAT ]]; then
            echoout "E182;" "check_dependencies(): there is a wrong dependencies in $COMMIT.txt: \"$DEPMLHNONFORMAT\""
            exit 1
        else
            echoout "I;" "check_dependencies(): All dependencies looks good"
        fi
    fi
}
check_release() {

    if [[ $NO_CHECK_RELEASE == "true" ]]; then
        echoout "I;" "check_release(): NO_CHECK_RELEASE $NO_CHECK_RELEASE, return"
        return
    fi
    echoout "I;" "check_release(): start, will check format of this: $RELEASE. MUST be 'MLH_Release#{d,ddd}/{year} or After_Release#...'"
    if [[ $RELEASE =~ ^(MLH|After)_Release#(.*) ]]; then
        RELNUM=${BASH_REMATCH[2]// /}
        if [[ ! $RELNUM =~ ^[0-9]{1,3}/[0-9]{2}$ ]]; then
            echoout "E180;" "check_release(): part afer '#' contain non-digits or too much/less digits: $RELNUM"
            exit 1
        fi
        RELYEAR=$(echo $RELNUM | cut -d/ -f 2)
        DATEYEAR=$(date +%y)
        let DATEYEAR2=DATEYEAR+1
        let DATEYEAR3=DATEYEAR-1
        if [[ $RELYEAR -ne $DATEYEAR && $RELYEAR -ne $DATEYEAR2 && $RELYEAR -ne $DATEYEAR3 ]]; then
            echoout "E183;" "check_release(): Release year not current and not next calendar year: current $DATEYEAR, release $RELYEAR"
            exit 1
        fi
    else
        echoout "E181;" "check_release(): commit not contain 'MLH_Release#' at begin. Not allowed release: $RELEASE"
        exit 1
    fi
    echoout "I181;" "check_release(): $RELEASE format correct"
}

parse_readme() {
    echoout "I;" "parse_readme(): start for $COMMIT.txt"

    if [[ -f $COMMIT.txt ]]; then
        echoout "I;" "parse_readme(): found $COMMIT.txt, start parsing"
        sed -i "s/\r//" $COMMIT.txt
        SUBJ=$(grep -m 1 -i ^Title $COMMIT.txt | tr -s ":, \r\n" " ") #cut -d':' -f 2 )
        SUBJ=${SUBJ//[Tt]itle/}
        VENDOR=$(grep -m 1 -i ^Vendor $COMMIT.txt | tr -s ":, \r\n" " " | grep -oP '(?<=Vendor[[:space:]])[/a-zA-Z ]+')
        #' mcedit highlight fix
        ## stackoverflow 369758
        ## strip from end shortest(%) some than var itself without all but space([![:blank:]]) from begin longest (##)
        VENDOR=${VENDOR%${VENDOR##*[![:blank:]]}}
        AUTHOR=$(grep -m 1 -i Author $COMMIT.txt | tr -s ":, \r\n" " " | grep -oP '(?<=Author[[:space:]])[/a-zA-Z ]+')
        #' mcedit highlight fix
        # remove trailing whitespace characters
        AUTHOR="${AUTHOR%"${AUTHOR##*[![:space:]]}"}"
        #"
        #  remove all spaces
        #   AUTHOR=${AUTHOR// /}
        JIRA_ID=$(grep -m 1 -E "^JIRA\s+?ID" $COMMIT.txt | tr -s ":," " " | grep -oP '(?<=ID[[:space:]])[0-9A-Z-]+')
        #    JIRA_ID=${JIRA_ID##JIRA ID}
        #    JIRA_ID=${JIRA_ID##JIRAID}
        #   COMMITER=$( curl -s $NEXUS_DEVPATH/$COMMIT/$COMMIT-commiter.info )
        #    RELEASE=$( grep -i ^Release $COMMIT.txt | tr -s ":, \r\n" " " | cut -d' ' -f 2- )
        RELEASE=$(grep -m 1 -i ^Release $COMMIT.txt | tr -s ":, \r\n" " " | grep -oP '(?<=Release[[:space:]])[0-9a-zA-Z/#_]+')
        echoout "I;" "parse_readme(): parse result(^ is dividers, not var parts): ^$VENDOR^, ^$AUTHOR^, ^$JIRA_ID^, ^$RELEASE^"
    else
        echoout "E011;" "parse_readme(): did not find file $COMMIT.txt"
        rm -vf $COMHEAD || true
        echo "не найден, нет $COMMIT.txt" >>$COMHEAD
        exit 1
    fi

    [[ -z "$SUBJ" ]] && echoout "E015;" "parse_readme(): did not found subject (title) in $COMMIT.txt"
    [[ -z "$VENDOR" ]] && echoout "E016;" "parse_readme(): did not found Vendor in $COMMIT.txt"
    [[ -z "$AUTHOR" ]] && echoout "E017;" "parse_readme(): did not found author in $COMMIT.txt"
    [[ -z "$RELEASE" ]] && echoout "E026;" "parse_readme(): did not found release in $COMMIT.txt"

    #rm -vf $COMHEAD || true
    echo "$SUBJ" >$COMHEAD
    echo "$VENDOR" >>$COMHEAD
    echo "$AUTHOR" >>$COMHEAD
    echo "$JIRA_ID" >>$COMHEAD
    echo "$RELEASE" >>$COMHEAD
    echoout "I;" "parse_readme(): saved SUBJ, VENDOR, AUTHOR, JIRAID,  RELEASE to $COMHEAD"
}

nexus_exist() {

    echoout "I;" "nexus_exist(): Start with \"$*\""
    if [[ $# -lt 1 ]]; then
        echo "nexus_exist(): Too few arguments. {what-to-check} (readme, distrib, targz) required."
        exit 1
    fi

    COMMAND="$1"

    case "$COMMAND" in
    "readme")
        URL=$NEXUS_DEVPATH/$COMMIT/$COMMIT.txt
        MESS1="test existence of readme $COMMIT.txt in $NEXUS_DEVPATH/$COMMIT/"
        ;;
    "distrib")
        URL=$NEXUS_RELPATH/$COMMIT/ST_$COMMIT.zip
        MESS1="test existence of $NEXUS_RELPATH/$COMMIT/ST_$COMMIT.zip, NO_DELIVERY= $NO_DELIVERY, P_CHECK_REDELIVERY= $P_CHECK_REDELIVERY"
        if [[ "$NO_DELIVERY" == "true" ]]; then
            echoout "I;" "nexus_exist(): NO_DELIVERY=$NO_DELIVERY (enabled), do not check distrib_exist() "
            return
        fi
        ;;
    "targz")
        MESS1="test existence of targz supply ST_$COMMIT.tar.gz in $NEXUS_DEVPATH/$COMMIT/"
        URL=$NEXUS_DEVPATH/$COMMIT/ST_$COMMIT.tar.gz
        ;;
    *)
        echoout "I;" "nexus_exist(): got not valid parameter  ^$COMMAND^, exit"
        return
        ;;
    esac

    echoout "I;" "nexus_exist(): $MESS1"
    curl_call "GET" "noauth" "resp" "nodata" "" "" "$URL" "-I"
    CURLOUT=$(echo "$CURLBODY" | tr '\r\n' '#' | cut -d'#' -f -5)
    echoout "I;" "nexus_exist(): curl HEAD response - $CURLOUT"

    case "$COMMAND" in
    "readme")
        if [[ "$CURLCODE" -eq "200" ]]; then
            echoout "I100;" "nexus_exist(): readme $COMMIT.txt exist, HTTP code: $CURLCODE, can continue"
        else
            echoout "E100;" "nexus_exist(): readme not exist at url $NEXUS_DEVPATH/$COMMIT/$COMMIT.txt ,  HTTP code: $CURLCODE"
            exit 1
        fi
        echoout "I;" "readme_exist(): Loading readme file for further use"
        curl_call "GET" "noauth" "noresp" "nodata" "" "" "$NEXUS_DEVPATH/$COMMIT/$COMMIT.txt" "-O"
        ;;
    "distrib")
        if [[ "$P_CHECK_REDELIVERY" == "true" && "$CURLCODE" -eq "200" ]]; then
            echoout "E101;" "nexus_exist(): Redelivery detected on $NEXUS_RELPATH/$COMMIT/ST_$COMMIT.zip"
            exit 1
        else
            echoout "I102;" "nexus_exist(): P_CHECK_REDELIVERY=$P_CHECK_REDELIVERY, Redelivery not detected or detect disabled, continue"
        fi
        ;;
    "targz")
        if [[ "$CURLCODE" -eq "200" ]]; then
            echoout "E110;" "nexus_exist(): File targz exists in nexus, but did not downloaded - nexus search bug!"
        else
            echoout "E113;" "nexus_exist(): File ST_$COMMIT.tar.gz not exist in nexus"
        fi
        ;;
    esac
}

host_exist() {
    cd $CI_PROJECT_DIR
    echoout "I;" "host_exist(): start, check if  supply $COMMIT =  branch $BRANCH (when building tag, for example)"
    # common func.if true = no branch or tag, false  = need to skip checks and set branch
    if check_branch; then
        echoout "I;" "host_exist(): is group vars file exist for branch/group $BRANCH in inventories/"
        if [[ ! -f inventories/group_vars/$BRANCH.yml ]]; then
            echoout "E020;" "host_exist(): file inventories/group_vars/$BRANCH.yml do not exist, FAIL to read group vars for this ansible group"
            exit 1
        fi
        BRANCHHOSTS=$(echo $ANSHOSTS | jq -r ".$BRANCH.hosts[]")
        for host in $BRANCHHOSTS; do
            echoout "I;" "host_exist(): check fbddir for $host host"
            FBDDIR=$(echo $ANSHOSTS | jq "._meta.hostvars[\"$host\"].somebase.fbddir")
            if [[ -n $FBDDIR && $FBDDIR != "null" ]]; then
                echoout "I;" "host_exist(): Host $host have $FBDDIR dbase dir in config"
            else
                echoout "E019;" "host_exist(): Host $host do not have dbase dir in config, error exit"
                exit 1
            fi
        done
        echoout "I;" "host_exist(): All hosts checked in ansible inventory successfully"

        echoout "I;" "host_exist(): Check if given branch $BRANCH is exist in git $PFHOSTNAME"
        [ -d $PFHOSTNAME ] && run_command "rm -vrf $PFHOSTNAME"
        run_command "mkdir -vp $PFHOSTNAME"
        cd $PFHOSTNAME
        echoout "I;" "host_exist(): current dir: $(pwd)"
        run_command "git init"
        run_command "git remote add $PFHOSTNAME $PFHOSTURL"
        BRGIT=$(git ls-remote --heads somebasehost | grep -vi mlh | cut -f 2 | cut -d'/' -f 3 | tr '\n' ' ')
        echoout "I;" "host_exist(): Got list of branches from $PFHOSTNAME: $BRGIT"
        ## match string in long substring like devnexthotfix
        if [[ "$BRGIT" == *"$BRANCH"* ]]; then
            echoout "I;" "host_exist(): Yes, branch $BRANCH exists in git $PFHOSTNAME, can continue"
        else
            echoout "E106;" "host_exist(): branch $BRANCH NOT exist among git $PFHOSTNAME branches"
        fi
    else
        echo "I;" "host_exist(): Skipping checks due to check_branch(). BRANCH=$BRANCH"
    fi
    echoout "I;" "host_exist(): All hosts checked in ansible inventory successfully"

    echoout "I;" "host_exist(): Check if given branch $BRANCH is exist in git $PFHOSTNAME"
    [ -d $PFHOSTNAME ] && run_command "rm -vrf $PFHOSTNAME"
    run_command "mkdir -vp $PFHOSTNAME"
    cd $PFHOSTNAME
    echoout "I;" "host_exist(): current dir: $(pwd)"
    run_command "git init"
    run_command "git remote add $PFHOSTNAME $PFHOSTURL"
    BRGIT=$(git ls-remote --heads somebasehost | grep -vi mlh | cut -f 2 | cut -d'/' -f 3 | tr '\n' ' ')
    echoout "I;" "host_exist(): Got list of branches from $PFHOSTNAME: $BRGIT"
    ## match string in long substring like devnexthotfix
    if [[ "$BRGIT" == *"$BRANCH"* ]]; then
        echoout "I;" "host_exist(): Yes, branch $BRANCH exists in git $PFHOSTNAME, can continue"
    else
        echoout "E106;" "host_exist(): branch $BRANCH NOT exist among git $PFHOSTNAME branches"
    fi
    cd $CI_PROJECT_DIR
    echoout "I;" "host_exist(): Return to root build dir"
    run_command "pwd"
}

check_jiraids() {
    echoout "I;" "check_jiraids(): start. try load ids from  $COMHEAD"
    if [[ -f $COMHEAD ]]; then
        echoout "I;" "check_jiraids(): found $COMHEAD, start checking"
        # sed {N}p - print N-th line
        JIRA_ID=$(sed -n 4p $COMHEAD)
    else
        echoout "E021;" "check_jiraids(): not found $COMHEAD, cannot check jiraid, error exit"
        exit 1
    fi
    declare -a JIRAFAILIDS
    echoout "I;" "check_jiraids(): will check jiraids: $JIRA_ID"
    OLDIFS=$IFS
    IFS=' '
    ## split with IFS to array
    ISSTYPESARR=($ISSTYPES)
    JIRAIDNUM=0
    #split string for cycle by IFS
    for JIRAID in $JIRA_ID; do
        ((JIRAIDNUM++))
        MATCH=0
        for TYPE in "${ISSTYPESARR[@]}"; do
            if [[ $JIRAID =~ ^${TYPE}(.*) ]]; then
                if [[ ${BASH_REMATCH[1]} =~ ^[0-9]+$ ]]; then
                    MATCH=1
                    break
                else
                    MATCH=-1
                    break
                fi
            fi
        done
        if [[ $MATCH -le 0 ]]; then
            JIRAFAILIDS+=($JIRAID)
        fi
    done
    if [[ $JIRAIDNUM -eq 0 ]]; then
        echoout "E014;" "check_jiraids(): No Jira ids ('JIRAID' with any spaces) found in $COMMIT.txt"
        exit 1
    elif [[ ${#JIRAFAILIDS[@]} -gt 0 ]]; then
        echoout "E010;  ^${JIRAFAILIDS[*]}^" "check_jiraids(): issue type (${ISSTYPES})-digit not allowed: ${JIRAFAILIDS[*]} "
        exit 1
    else
        echoout "I104;" "check_jiraids(): Checked $JIRAIDNUM JIRA IDS: $JIRA_ID : format correct"
    fi
    IFS=$OLDIFS
}

unpack_supplytargz() {
    echoout "I;" "unpack_supplytargz(): start"
    tar -xf ST_$COMMIT.tar.gz
    EXTAR=$?
    if [[ "$EXTAR" -gt "0" ]]; then
        echoout "E;" "unpack_supplytargz(): Supply dir looks as:"
        LSERR=$(ls -l Supply/)
        echoout "E;" "unpack_supplytargz(): $LSERR"
        echoout "E106;" "unpack_supplytargz(): Cannot find ST_$COMMIT.tar.gz or another error: code $EXTAR, see ls above"
        exit 1
    fi
    if [[ -f ST_$COMMIT/CR_contents.txt ]]; then
        cp -v ST_$COMMIT/CR_contents.txt $CI_PROJECT_DIR
        echoout "I;" "unpack_supplytargz(): CR contents file extracted: $(ls -l CR_contents.txt) "
    else
        echoout "EE;" "unpack_supplytargz(): CR contents file did not found in ST_$COMMIT/CR_contents.txt  "
    fi

}

check_supplytargz_author() {
    echoout "I;" "check_supplytargz_author(): start"
    if [[ -f $COMHEAD ]]; then
        echoout "I;" "check_supplytargz_author(): Check author field in $COMHEAD"
        AUTHOR=$(sed -n 3p $COMHEAD)
        AUTHCR=$(cat CR_contents.txt | cut -d"|" -f 5 | sort -u | tr "\n" " ")
        if [[ -z $AUTHOR ]]; then
            echoout "I;" "check_supplytargz_author(): Author missed in $COMHEAD, got it from  CR_contents.txt: $AUTHCR. Save it with 3rd $COMHEAD-author.txt line"
            AUTHCR=${AUTHCR}"(from CR_contents.txt)"
            sed "3s/.*/$AUTHCR/" $COMHEAD >author-$COMHEAD
        else
            echoout "I;" "check_supplytargz_author(): Author is defined in $COMHEAD: $AUTHOR"
            AUTHCRWS=$(echo $AUTHCR | sed 's/<.*>//' | tr -d [:blank:])
            AUTHCRWS2=${AUTHCRWS// /}
            AUTHORWS=${AUTHOR// /}
            if [[ $AUTHORWS != $AUTHCRWS2 ]]; then
                echoout "I;" "but it differ from CR contents author name: $AUTHCRWS"
            fi
        fi
    else
        echoout "EE;" "check_supplytargz_author(): $COMHEAD file did not found in $(pwd)  "
    fi
}

check_supplytargz_codepage() {
    echoout "I;" "check_supplytargz_codepage(): start, P_CHECK_ENC = $P_CHECK_ENC"
    if [[ $P_CHECK_ENC == "true" && -d ST_$COMMIT ]]; then
        FFILES=$(find ST_$COMMIT -type f -printf '%p\n')
        FILESARR=("$FFILES")
        IFS=$'\n'
        for FILEP in ${FILESARR[@]}; do
            FWORDS=$(echo "$FILEP" | wc -w)
            if [[ "$FWORDS" -gt 1 ]]; then
                echoout "E;" "check_supplytargz_codepage(): file with spaces in name: $FILEP"
                CPAGEERR+=("$FILEP : Проверьте, должен ли этот файл быть по этому пути. Возможно, его надо переместить в docs/utp")
            else
                CPAGE=$(enca -i -L ru "$FILEP")
                #        echo $FILEP ":" $CPAGE
                if [[ $CPAGE == "ASCII" || $CPAGE == "UTF-8" ]]; then
                    echoout "I;" "check_supplytargz_codepage(): $CPAGE: right codepage for $FILEP"
                elif [[ "$CPAGE" != "???" ]]; then
                    echoout "E;" "check_supplytargz_codepage(): $CPAGE: wrong codepage for  $FILEP"
                    CPAGEERR+=("$FILEP : $CPAGE")
                    echoout "I;" "check_supplytargz_codepage(): encode $FILEP to UTF-8"
                    enca -L ru -x UTF-8 "$FILEP"
                    EXEN=$?
                    if [[ $EXEN -gt 0 ]]; then
                        echoout "E022;" "check_supplytargz_codepage(): enca reencoding of $FILEP broken. exit"
                        exit 1
                    fi
                else
                    echoout "E;" "check_supplytargz_codepage(): codepage ^$CPAGE^ unknown for FILE $FILEP"
                    CPAGEREASON=$(enca -d -L ru "$FILEP")
                    CPAGEERR+=("$FILEP : $CPAGE - $CPAGEREASON")
                fi
            fi
        done
    fi
    if [[ ${#CPAGEERR[@]} -gt 0 ]]; then
        #     echoout "E;" "${EXITMESS//$'\\n'}"
        echoout "E114;" "check_supplytargz_codepage(): Found files in wrong codepage or name, write it to $CPAGECHKFILE :"
        for line in "${CPAGEERR[@]}"; do
            echoout "E;" "- $line"
            echo "$line" >>$CPAGECHKFILE
        done
        echoout "I;" "check_supplytargz_codepage(): pack supply again with re-encoded files to ST_$COMMIT-reenc.tar.gz "
        #    run_command "tar -czvf ST_$COMMIT-reenc.tar.gz ST_$COMMIT"
        run_command "/bin/zip -0 -r ST_$COMMIT-reenc.zip ST_$COMMIT/"
        echoout "E;" "check_supplytargz_codepage(): fail pipeline, move to step send errormail"
        exit 1
    # zip not needed, will not upload and fail
    #    echoout "I;" "download rest files, pack zip supply again with new ST_$COMMIT.tar.gz "
    #    ./scripts/nexus-do.sh nexusdownload repack
    else
        echoout "I;" "check_supplytargz_codepage(): did not find any files with wrong codepage"
    fi
}

check_targz_compare_builders() {
    echoout "I;" "check_targz_compare_builders(): start"
    cd $CI_PROJECT_DIR
    run_command "mkdir -vp st_2"
    tar -C st_2 -xf ST_$COMMIT-2.tar.gz
    EXTAR=$?
    if [[ "$EXTAR" -gt "0" ]]; then
        echoout "E;" "tar has errors"
        exit 0
    fi
    run_command "rm -vf sha1sumfiles.txt sha1sumfiles-2.txt || true"
    if [[ -d ST_$COMMIT && -s st_2/ST_$COMMIT ]]; then
        FILES=$(find ST_$COMMIT -mindepth 2 -type f -printf '%p ')
        for FILE in $FILES; do
            SHASUM=$(sha1sum $FILE)
            SHASUMPY=$(sha1sum st_2/$FILE)
            echo $SHASUM >>sha1sumfiles.txt
            SHASUMPYSUM=$(echo $SHASUMPY | cut -d' ' -f 1)
            SHASUMPYFILE=$(echo $SHASUMPY | cut -d' ' -f 2 | cut -d/ -f 2-)
            echo "$SHASUMPYSUM $SHASUMPYFILE" >>sha1sumfiles-2.txt
            echoout "I;" "check_targz_compare_builders(): compute sha1sum for $FILE and st_2/$FILE"
        done
    fi
    cat sha1sumfiles.txt | sort >sha1sumfiles-sort.txt
    cat sha1sumfiles-2.txt | sort >sha1sumfiles-2-sort.txt
    echoout "I;" "check_targz_compare_builders(): below diff sha1sumfiles-sort.txt"
    #run_command "diff -iwB -u -U1 sha1sumfiles-sort.txt sha1sumfiles-2-sort.txt"
    DIFF=$(diff -iwB -U 0 sha1sumfiles-sort.txt sha1sumfiles-2-sort.txt 2>&1)
    EXDIFF=$?
    if [[ $EXDIFF -eq 1 ]]; then
        RESDIFF=$(echo "$DIFF" | tail -n +4)
        echoout "E;" "check_targz_compare_builders(): files different: sha1sumfiles-sort.txt sha1sumfiles-2-sort.txt, save to $RESDIFFFILE"
        echoout "E;" "check_targz_compare_builders(): $RESDIFF"
        echo "$RESDIFF" >$RESDIFFFILE
    elif [[ $EXDIFF -gt 1 ]]; then
        echoout "E;" "check_targz_compare_builders(): error in diff sha1sumfiles-sort.txt sha1sumfiles-2-sort.txt "
        echoout "E;" "check_targz_compare_builders(): $DIFF"
    fi
    echoout "I;" "check_targz_compare_builders(): end"

}

check_supplytargz() {

    echoout "I;" "check_supplytargz(): start"
    unpack_supplytargz
    check_supplytargz_author
    check_supplytargz_codepage
    ####check_targz_compare_builders

}

check_datajson() {

    echoout "I;" "check_datajson(): Check generated data.json file for version/path/jiraid compilance with current task"

    if [[ -f $COMHEAD && -f data.json ]]; then
        # sed {N}p - print N-th line
        ## sort can use only lines delinited by \n, -t cannot work
        ## got sorted string without spaces
        JIRA_IDS=$(sed -n 4p commheader.txt | tr ' ' '\n' | sort | tr -d '\n')
    else
        echoout "E610;" "check_datajson(): files $COMHEAD or data.json not found"
        exit 1
    fi
    #echoout "I;" "get 'version' from commit var: $COMMIT"
    #echoout "I;" "get 'supplyPath' from commit var: $URL"
    #echoout "I;" "get 'issues' from $COMHEAD: $JIRA_IDS"

    JSONVER=$(jq -r '.version' data.json)
    JSONPATH=$(jq -r '.supplyPath[0]' data.json)
    ## -j raw one-line (without "\n")
    JSONISS=$(jq -j '.issues|sort|.[]' data.json)
    JSONREL=$(jq -r '.Release' data.json)

    #echoout "I;" "get 'version' from data.json: $JSONVER"
    #echoout "I;" "get 'supplyPath' from data.json: $JSONPATH"
    #echoout "I;" "get 'issues' from data.json: $JSONISS"

    if [[ -z $JSONVER || $COMMIT != $JSONVER ]]; then
        CHKDATA+=("commit%version wrong in data.json: \"$COMMIT\"%\"$JSONVER\"")
    fi
    if [[ -z $JSONPATH || $URL != $JSONPATH ]]; then
        CHKDATA+=(" url%supplyPath wrong in data.json: \"$URL\"%\"$JSONPATH\"")
    fi
    if [[ -z $JSONISS || $JIRA_IDS != $JSONISS ]]; then
        CHKDATA+=(" JIRA_IDS%JSONISS array wrong in data.json: \"$JIRA_IDS\"%\"$JSONISS\"")
    fi
    if [[ -z $JSONREL || $RELEASE != $JSONREL ]]; then
        CHKDATA+=(" RELEASE%JSONREL array wrong in data.json: \"$RELEASE\"%\"$JSONREL\"")
    fi

    if [[ ${#CHKDATA[@]} -gt 0 ]]; then
        echoout "E611;" "check_datajson(): Data json formed incorrectly:"
        for line in "${CHKDATA[@]}"; do
            echoout "E;" "- $line"
        done
        exit 1
    else
        echoout "I;" "check_datajson(): commit/version, url/supplypath, jira_ids/json_issues, release/Release compared ok"
    fi

}

#------------------ main -------------------------

echoout "I;" "main(): Start $0 $*"
if [[ $# -lt 1 ]]; then
    echo "Too few arguments. command required."
    print_usage
    exit 1
fi

COMMAND="$1"
EXISTING="$2"

if [ -f $COMHEAD ]; then
    # sed {N}p - print N-th line
    # if error, then subj will defined later
    RELEASE=$(sed -n 5p $COMHEAD | tr -d ' ')
fi

case "$COMMAND" in
"nexusexist")
    nexus_exist $EXISTING
    ;;
"readmeexist")
    readme_exist
    ;;
"distribexist")
    distrib_exist
    ;;
"parsereadme")
    parse_readme
    ;;
"hostexist")
    host_exist
    ;;

"checkcommit")
    check_commit
    ;;
"checkrelease")
    check_release
    ;;
"checkdependencies")
    check_dependencies
    ;;
"checkjiraids")
    check_jiraids
    ;;
"checksupplytargz")
    check_supplytargz
    ;;
"checkdatajson")
    check_datajson
    ;;
*)
    PROG=$(basename $0)
    echoout "E192;" "main(): Command not suitable : $COMMAND in $*"
    print_usage
    exit 1
    ;;
esac
