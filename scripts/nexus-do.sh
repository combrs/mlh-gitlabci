#!/bin/bash 

set -o pipefail

CURDIR=`pwd`
CI_PROJECT_DIR=${CI_PROJECT_DIR:-"$CURDIR"}
CI_JOB_NAME=${CI_JOB_NAME:-"Upload"}
CI_JOB_ID=${CI_JOB_ID:-"234223"}
RELNOTESDIR=${RELNOTESDIR:-$CI_PROJECT_DIR}
COMMIT=${COMMIT:-"MLH-8888"}
P_CHECK_ANSBRANCH=${P_CHECK_ANSBRANCH:-"false"}
MAIL_LIST=${MAIL_LIST:-"\"mlykov@mlh.ru\""}
DEBUG_MAIL=${DEBUG_MAIL:-"\"mlh214277@dev.mlh\""}
MAIL_LIST_REPORT=${MAIL_LIST_REPORT:-"mlykov@mlh.ru, mlh214277@dev.mlh"}
P_SEND_NOTIFICATION=${P_SEND_NOTIFICATION:-"false"}
P_CHECK_REDELIVERY=${P_CHECK_REDELIVERY:-"false"}
READMESFILE=${READMESFILE:-"readmesexcess.json"}
CPAGECHKFILE=${CPAGECHKFILE:-"cpagechk.txt"}
MLH_PROXY_URL=${MLH_PROXY_URL:-"10.64.40.155"}
MLH_PROXY_PORT=${MLH_PROXY_PORT:-"8080"}
PFHOST_BR_TOKEN=${PFHOST_BR_TOKEN:-"sxzKdBEo2bCzZgTZT_Zb"}
PFHOSTNAME=${PFHOSTNAME:-"somebasehost"}
PFHOSTURL=${PFHOSTURL:-"http://somebaseci-git:$PFHOST_BR_TOKEN@ci.corp.dev.mlh/$PFHOSTNAME/$PFHOSTNAME.git"}
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
SUPPLY="ST_$COMMIT.tar.gz"
README="$COMMIT.txt"

source ./scripts/common_func.sh

print_usage() {
echoout "     Usage:
              $PROG nexusdownload [targz] - download supply files from nexus (only targz or rest but targz)
              $PROG nexusupload {supply/atresult} - upload files to nexus release/: supply zip or attest cucumber.xml"
}

urlencode() {
    # urlencode <string>
    pat="[a-zA-Z0-9.:/_-]"
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            $pat) printf "%s" "$c" ;;
#            *) printf "$c" | xxd -p -c1 | while read x; do echo "--$x--"; printf "%%%s" "$x"; done
            *) printf "%s" "$c" | xxd -p -c1 | while read x; do printf "%%%s" "$x"; done
        esac
    done
}

urldecode() {
    #urldecode <string>
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

nexus_search() {
echoout "I;" "nexus_search(): Search files in nexus for repository=somebase and group=$NEXUS_SEARCHPATH" 
# remove trailing / for search
READMNEED=0
READMEXCESS=0
curl_call "GET"  "basic" "resp" "nodata" "$NEXUS_AUTH" "" "$NEXUS_URL/service/rest/v1/search?repository=somebase&group=/$NEXUS_SEARCHPATH"
#nexussearchres=$(curl -s "$GLH_CLOUD/service/rest/v1/search?repository=somebase&group=/$SEARCHPATH" -u $MAVEN_REPO_USER:$MAVEN_REPO_PASS )
length=$( echo "$CURLBODY" | jq '.items | length' )
if [[ "$length" -eq "0" ]]; then
        echoout "E102;" "nexus_search(): Did not find anything suitable in nexus, exiting with error"
        exit 1
else
         echoout "I;" "nexus_search(): Found $length suitable files to download"
fi       
for ((num=0; num < length; num++)); do
    nexusName=$( echo "$CURLBODY" | jq -r ".items[$num].name" )
    nexusNamesh=${nexusName//$NEXUS_REMOVEPATH/} 
    if [[  $nexusName =~ \.txt$  ]]; then
        READMES+=( $nexusNamesh )
        if [[ $nexusNamesh == "$README" ]]; then
            echoout "I;" "nexus_search(): found supply readme file $nexusNamesh"
            (( READMNEED +=1 ))
        else
            echoout "I;" "nexus_search(): found excess readme file ^$nexusNamesh^"
            (( READMEXCESS +=1 ))
        fi
    fi
done
echoout "I;" "nexus_search(): found readme files: ${READMES[*]}, $READMNEED for current supply and $READMEXCESS excess"
if [[ $READMNEED -lt 1 && $READMEXCESS -gt 0 ]]; then
    echo "${READMES[*]}" > $READMESFILE
    echoout "E115;" "nexus_search(): only excess readme files found"
fi
echo "$CURLBODY" > $NEXUSRESFILE

}

nexus_downloadfile() {
nurl="$1"
nname="$2"
echoout "I;" "n.d.file(): getting ^$nexusNamesh^" 
curl_call "GET"  "basic" "noresp" "nodata" "$NEXUS_AUTH" "" "$nurl" "$nname" "" "size"
if [[ "$CURLCODE" -eq "200" ]]; then
        echoout "I;" "n.d.file(): [size $CURLSIZE ] SUCCESS got $nexusNamesh"
elif [[ "$CURLCODE" -eq "404" ]]; then
       echoout "E104;" "n.d.file(): [code $CURLCODE ] (nexus bug) FAIL got $nexusNamesh (wrong url), remove html file downloaded instead it"
       RMOUT=$( rm -vf "$nname" )
       if [ -n "$RMOUT" ]; then
          echoout "I;" "$RMOUT" 
       else
          echoout "E;" "n.d.file(): failed remove file $nname"
       fi
else
       echoout "E109;" "n.d.file(): [code $CURLCODE ]  FAIL got $nexusNamesh , see code"
fi
}

nexus_checkdownsupply() {
PACK=$1
echoout "I;" "nexus_checkdownsupply(): start, arg ^$PACK^, show 'pwd' below"
## arg="pack" if called from nexus_pack
## nothing if called from nexus_download

cd $CI_PROJECT_DIR
run_command "pwd"
if [ -f $SUPPLY ]; then
    echoout "I;" "nexus_checkdownsupply(): Supply exist on disk. it will copied to Supply/  if called from nexus_pack()"
    [[ $PACK == "pack" ]] && run_command "cp -v $SUPPLY Supply/"   || echoout "I;" "not pack, continue"
else
    ./scripts/checksupply.sh nexusexist targz
    echoout "E111;" "nexus_checkdownsupply(): $SUPPLY did not exist on disk. cannot continue, error exit!"
    exit 1
fi

}

nexus_pack() {

#REPACK="$1"
echoout "I;" "nexus_pack(): start, arg is ^$REPACK^, show 'pwd'"
cd $CI_PROJECT_DIR/Temp/
run_command "pwd"
## other than $COMMIT.txt for artifacts?
##run_command "cp -v *.txt ../"
run_command "mkdir -vp $CI_PROJECT_DIR/Supply"
run_command "mkdir -vp $CI_PROJECT_DIR/Docs"
echoout "I;" "copying files downloaded from nexus $NEXUS_URL to supply folders for zip" 
run_command "cp -v *.war ../Supply"
run_command "cp -v *.ear  ../Supply"
run_command "cp -v *.EXP ../Supply"
## for $COMMIT.txt
run_command "cp -v ../$README ../Docs"
## other than $COMMIT.txt
run_command "cp -v *.txt ../Docs"
run_command "cp -v *.docx ../Docs"
run_command "cp -v *.doc ../Docs"
run_command "cp -v *.sh ../Docs"
## for artifacts
echoout "I;" "copying files to root folder for upload as artifacts"
run_command "cp -v *.doc ../"
run_command "cp -v *.docx ../"
run_command "cp -v *.sh ../"
run_command "cp -v $COMMIT-commiter.info ../"

nexus_checkdownsupply pack
# zip not needed, will not upload and fail   
#if [[ $REPACK == "repack" ]]; then 
#    ZIPNAME=ST_$COMMIT-repack.zip
#    echoout "I;" "Zipping supply with re-encoded code page files, zip name: $ZIPNAME"
#else

#    echoout "I;" "Zip supply name: $ZIPNAME"
#fi

ZIPNAME=ST_$COMMIT.zip
echoout "I;" "Zipping Files in Supply/ Docs/"
run_command "zip -0 -r $ZIPNAME Supply/ Docs/"
if [ ! -f $ZIPNAME ]; then
    echoout "E103;" "Zip did not created file $ZIPNAME, exit"
    exit 1
else
    echoout "I107;" "Zip created: file $ZIPNAME"
fi    
echoout "I;" "end" 
#rm -rf Docs/ Supply/ Temp/

}

nexus_download() {

## if not "targz", then rest
TARGET="$1"
run_command "mkdir -vp $CI_PROJECT_DIR/Temp"
echoout "I;" "nexus_download(): load search res file from nexus_search() if exist"
if [ -f $NEXUSRESFILE ]; then
    nexussearchres=$( cat $NEXUSRESFILE )
else
    echoout "E108;" "nexus_download(): file $NEXUSRESFILE not found, cannot download"
    exit 1
fi
length=$( echo "$nexussearchres" | jq '.items | length' )
echoout "I;" "Supply $COMMIT: Found $length files in nexus folder, show 'pwd'"
cd $CI_PROJECT_DIR/Temp/
run_command "pwd"
for ((num=0; num < length; num++)); do

    nexusName=$( echo "$nexussearchres" | jq -r ".items[$num].name" )
    numAssets=$( echo "$nexussearchres" | jq -r ".items[$num].assets|length" )
    if [[ $numAssets -eq 0 ]]; then
        echoout "E112;" "nexus_download(): nexussearch found item $nexusName, but it not contains any downloadadble assets"
        continue
    fi
    nexusUrl=$( echo "$nexussearchres" | jq -r .items[$num].assets[0].downloadUrl )
    nexusNamesh=${nexusName//$NEXUS_REMOVEPATH/} 
    if [[ $TARGET == "targz" ]] ; then
        if [[  $nexusName =~ \.tar\.gz$  ]]; then
            cd $CI_PROJECT_DIR/
            nexus_downloadfile "$nexusUrl" "$nexusNamesh"
            if [ "$CURLCODE" -ne "200" ]; then
#                echoout "I;" "nexus_download(): Supply downloaded, can continue: $(ls -l *.tar.gz)"
#                echoout "I;" "file $nexusNamesh: skip rest downloads, exit successfully "
#                exit 0
#            else
                echoout "E105;" "nexus_download(): [code "$CURLCODE" ] Supply $SUPPLY NOT downloaded, cannot continue, error exit!"
                exit 1
            fi
        else ## target targz, file not targz
            echoout "I;" "nexus_download(): skip download other than targz files, download target targz,  file $nexusNamesh "
            continue
        fi
    else  ## not targz 
        echoout "I;" "nexus_download(): try with $nexusNamesh"
        if [[ $nexusName =~ \.tar\.gz$  ]]; then
            echoout "I;" "nexus_download(): file $nexusNamesh: skip download tar.gz file, use nexusdownload targz for that, continue"
            continue
        elif [[ $nexusNamesh == "$README" && -f ../$README ]]; then
            echoout "I;" "nexus_download(): file $nexusNamesh: already downloaded at earlier pipeline stage, continue"
            continue
        fi
#        nexusUrlU=$nexusUrl
#	    if echo $nexusNamesh | grep -vE '^[a-zA-Z0-9._-]+$' > /dev/null; then
	        echoout "I;" "nexus_download(): Urlencoding for url:urlencode()"
	        nexusUrlU=$(urlencode "$nexusUrl")
	        # convert all but this (alnum or punct) symbols in saved name to underscores
            nexusNameshU=$( echo -n "$nexusNamesh" | tr -c '[:alnum:][:punct:]' '_' )
            echoout "I;" "nexus_download(): Urlencode result (to load): $nexusUrlU"
            echoout "I;" "nexus_download(): Underscore result (to save): $nexusNameshU"
#	    fi
	    nexus_downloadfile "$nexusUrlU" "$nexusNameshU"
    fi    ## if target=targz
done

## if after full found files cycle targz not downloaded, but target is targz, then not run nexus_pack, but fail
## if target is not targz, then pack full result (stage - download_rest)
if [[ $TARGET == "targz" ]]; then
     nexus_checkdownsupply
else
    echoout "I;" "nexus_download(): not targz call, pack files with nexus_pack"           
    nexus_pack 
fi
}


nexus_upload() {

if [[ -z "$1" ]]; then
    echoout "E;" "nexus_upload(): Too few arguments. 'upload type: supply/atresult' required"
    print_usage
    exit 0
fi
## Disable auto-repackage with reencoded codepage   
#if [[ -f $CPAGECHKFILE ]]; then
#    echoout "E;" "nexus_upload(): $CPAGECHKFILE exists, rename repacked ST_$COMMIT-repack.zip from check_targz"
#    ZIPFILE=ST_$COMMIT-repack.zip
#    run_command "mv -vf ST_$COMMIT-repack.zip ST_$COMMIT.zip"
#else
#    echoout "E;" "nexus_upload(): $CPAGECHKFILE not exists, upload usual ST_$COMMIT.zip, codepage correct in all files"
#    ZIPFILE=ST_$COMMIT.zip
#fi

ARG="$1"
case "$ARG" in
    "supply" )
        UPLFILE=ST_$COMMIT.zip
        UPLURL="$NEXUS_RELPATH/$COMMIT"
        INUM=I111
    ;;
    "atresult" )
        UPLFILE="cucumber.xml"
        UPLURL=$NEXUS_RELPATH
        INUM=I
    ;;
esac

if [[ "$NO_DELIVERY" != "true" ]]; then
    echoout "I;" "NO_DELIVERY=$NO_DELIVERY,  disabled"
    if [ -f $UPLFILE ]; then
        echoout "I;" "Upload file $UPLFILE to $UPLURL" 
        curl_call "upload"  "basic" "resp" "nodata" "$NEXUS_AUTH" "" "$UPLURL/$UPLFILE" "$UPLFILE"
    	## -v gives more output than -I, with '*, >,<'
        CURLOUT=$(echo "$CURLBODY" |  grep "^<" |  tr '\r\n' '#'| cut -d'#' -f 2-7 )
        echoout "I;" "upload nexus responce: $CURLOUT"
    	if [[ "$CURLCODE" -eq "201" ]]; then
    	      echoout "$INUM;" "Successful upload file $UPLFILE to $UPLURL" 
            else 
              echoout "E501;" "Failed upload file $UPLFILE to $UPLURL, http code $CURLCODE" 
        fi
    fi
else
    echoout "I;" "NO_DELIVERY=$NO_DELIVERY, enabled, do not check distrib_exist() and do not upload anything"
fi
echoout "I;" "end" 
}

# ----------------------- main -------------------------

echoout "I;" "Start $0 $*"
##if [[ "$#" -lt "2" || -z $2 ]]; then
if [[ "$#" -lt "1" ]]; then
    PROG=`basename $0`
    echoout "E;" "Too few arguments: $*"
    print_usage
    exit 1
fi

COMMAND=$1
## if second argument absent, env var is cleared
## but now all calls using second arg as required above
### update: as in jira-api, use args in function immediately
##COMMIT=$2
##DOWNPAR=$3

case "$COMMAND" in
    "nexussearch" )
        nexus_search 
    ;;
    "nexusdownload" )
        nexus_download "$2"
    ;;
    "nexusupload" )
        nexus_upload "$2" 
    ;;
    * )
        PROG=`basename $0`
        echoout "E192;" "Command not suitable : $COMMAND in $*" 
        print_usage
	exit 1
esac
