#!/bin/bash

# v2 13-05-2020: add functions
# v3 15-05-2020: fix stranges, add comments, create confluence doc
# v4 17-05-2020: add copyarchive/p_copy() by scp; add mpi echotest after restore

#set -o pipefail

PROJECT_DIR=$(pwd)
JOB_NAME="$0"
echoout() { printf "%s $0 %s\n" "$1" "$2" | tee -a "$PROJECT_DIR"/"$JOB_NAME".stderr; }
print_usage() {
    PROG="$0"
    echoout "E;" "Usage: 
        $PROG archive {basename}: example: archive hotfix  - stop, kill, tar, gzip to /tmp/
        $PROG restore {archive-name}: example: restore /tmp/hotfix-333.tar.gz - gunzip, untar, start base
	    $PROG scainstall {archive-name}: example: scainstall /tmp/SCA-20.tar - unarchive to /fbd/
        $PROG copyarchive {any-file}: example: copyarchive /tmp/hotfix-333.tar.gz - copy by scp to fixed set of hosts
"
}

p_killmtm() {
    echoout "I;" "p_killmtm(): kill remaining processes"
    ps ax | grep -E '(mum|mtm)' | grep -i ${BASEN}
    kill $(ps ax | grep -E '(mum|mtm)' | grep -i ${BASEN} | cut -d" " -f 2)
    sleep 2
    echoout "I;" "p_killmtm(): remaining processes after kill"
    ps ax | grep -E '(mum|mtm)' | grep -i ${BASEN}
}


p_archive() {

    BASEN="$1"

    if [[ -z "$BASEN" ]]; then
        echoout "E;" "p_archive(): Argument {basename} required"
        print_usage
        exit 1
    fi

    if [[ "/${BASEN}" -ef "/fbd/${BASEN}" ]]; then
        echoout "I;" "p_archive(): base symlink exist, point to existing base: $(ls -l /${BASEN})"
    else
        echoout "E;" "p_archive(): given argument ^${BASEN}^ is not existing base name"
        print_usage
        exit 1
    fi

    echo "running processes to stop for ${BASEN}"
    ~/mpi /${BASEN}
    ~/deployInstance.sh ${BASEN} stop
    ~/mpi /${BASEN}

    p_killmtm
    echo "$(date) start tar archiving to /tmp/${BASEN}-$(hostname)-${DAT}.tar"
    #'
    cd /fbd
    tar -cf /tmp/${BASEN}-$(hostname)-${DAT}.tar ${BASEN}/
    echo "$(date) end tar archiving, start gzipping to /tmp/${BASEN}-$(hostname)-${DAT}.tar.gz"
    gzip /tmp/${BASEN}-$(hostname)-${DAT}.tar
    # scp /tmp/${BASEN}-$(hostname)-$(date +%F).tar.gz somecred@10.203.94.27:/fbd
    # scp /fbd/SCA-20.tar.gz somecred@10.203.94.27:/fbd
    echo "$(date) end gzipping"

    echo "starting back ${BASEN}"
    ~/deployInstance.sh ${BASEN} start
    ~/mpi /${BASEN}
    echo "testing ${BASEN}"
    ~/mpi --action ECHOTEST /${BASEN}

}

p_sca_unarchive() {

    cd /fbd
    if [[ -d SCA63001A ]]; then
        echo "/fbd/SCA63001A exists, only create link /SCA"
        sudo ln -fs /fbd/SCA63001A /SCA
    else
        echo "/fbd/SCA63001A not exist, REQUIRED SCA GTM not installed."
        TARFILE="$1"
        if [[ -z "$TARFILE" ]]; then
            echo "To install file /fbd/SCA-20.tar.gz or /fbd/SCA-20.tar will be used or rerun script with command scainstall"
            TARFILE=/fbd/SCA-20.tar.gz
            [[ -f $TARFILE ]] || TARFILE=/fbd/SCA-20.tar
            echoout "I;" "p_sca_unarchive(): file by default: ^$TARFILE^"
        else
            echoout "I;" "p_sca_unarchive(): got arg ^$TARFILE^"
        fi

        if [[ -f $TARFILE ]]; then
            if [[ $TARFILE =~ \.tar\.gz$ ]]; then
                echo "gzipped file, gunzip it"
                gunzip $TARFILE
                TARFILE=${TARFILE%.gz}
                echo "new file name: ^$TARFILE^"
            fi
            echo "$(date) Start with tar unarchiving file ^$TARFILE^ (full path required if not in /fbd)"
            tar -xf $TARFILE -C /fbd
            echo "$(date) end tar ^$TARFILE^ unarchiving, fix gtmsecshrdir/ "
            chmod 755 SCA63001A/gtm_dist/gtmsecshrdir/
            chmod 755 SCA63001A/gtm_dist/utf8/gtmsecshrdir/
            tar -xf $TARFILE SCA63001A/gtm_dist/gtmsecshrdir/gtmsecshr
            tar -xf $TARFILE SCA63001A/gtm_dist/utf8/gtmsecshrdir/gtmsecshr
            echo "$(date) end fix gtmsecshrdir/ "
            sudo ln -fs /fbd/SCA63001A /SCA
        else
            echo "^$TARFILE^ tarfile not exist, give right path for install SCA: scainstall {file}"
            print_usage
            exit 1
        fi
    fi

}

p_restore() {

    cd /fbd
    if [[ -d SCA63001A && -L /SCA ]]; then
        echo "/fbd/SCA63001A and link /SCA exists"
    else
        p_sca_unarchive
    fi
    TARFILE="$1"
    DAT=$(date +%F-%T)
    if [[ ! -f "$TARFILE" ]]; then
        echo "file ^$TARFILE^ does not exist, exit"
        exit 1
    fi
    echo "Start with tar file ^$TARFILE^ (full path required if not in same folder)"
    BASEN=$(basename "$TARFILE" | cut -d- -f 1)
    echo "base name from tar file name" "$BASEN"

    if [[ -d /fbd/${BASEN} ]]; then
        echo "directory /fbd/$BASEN already exist. stop base $BASEN"
        ~/deployInstance.sh ${BASEN} stop
        echo "processes holding $BASEN"
        MTMPROCS=$(ps ax | grep -i ${BASEN} | grep -Ei '(mtm|mum)')
        #'
        if [[ -n "$MTMPROCS" ]]; then
            p_killmtm
        #'
        else
            echo "no processes found. rename /fbd/${BASEN} to /fbd/${BASEN}-${DAT}"
            mv -f /fbd/${BASEN} /fbd/${BASEN}-${DAT}
        fi
    else
        echo "directory /fbd/$BASEN not exist, unarchive will create it"
    #    mkdir /fbd/$BASEN
    fi

    FTYPE=$(file $TARFILE)
    echo $FTYPE

    if [[ $TARFILE =~ \.tar\.gz$ ]]; then
        echo "gzipped file, gunzip it"
        gunzip $TARFILE
        TARFILE=${TARFILE%.gz}
        echo "new file name: ^$TARFILE^"
    fi
    echo "tar file contents begin:"
    tar -tf $TARFILE | head -3
    EXST=$?
    if [[ "$EXST" -ne "0" ]]; then
        echo "tar or head error: $EXST, cannot continue"
        exit $EXST
    fi

    echo "start unarchive file $TARFILE to /fbd"
    cd /fbd
    tar -xf $TARFILE
    echo "end unarchive, check symlink for /${BASEN}"
    if [[ "/${BASEN}" -ef "/fbd/${BASEN}" ]]; then
        echo "symlink exist: $(ls -l /${BASEN})"
    else
        echo "symlink NOT exist: $(ls -l /${BASEN}). create it"
        sudo ln -s /fbd/${BASEN} /${BASEN}
        echo "symlink exist now? $(ls -l /${BASEN})"
    fi

    echo "starting ${BASEN}"
    ~/deployInstance.sh ${BASEN} start
    ~/mpi /${BASEN}
    echo "testing ${BASEN}"
    ~/mpi --action ECHOTEST /${BASEN}


}

p_copy() {

    TARFILE="$1"
    if [[ ! -f "$TARFILE" ]]; then
        echoout "E;" "p_copy(): file ^$TARFILE^ does not exist, exit"
        exit 1
    fi
    echoout "I;" "p_copy(): Start with tar file ^$TARFILE^ (full path required if not in same folder)"
    for i in 27 28 29 30 32; do
        echoout  "copy ^$TARFILE^ to $i"
        scp $TARFILE somecred@10.203.94.$i:/fbd
        #scp /fbd/SCA-20.tar.gz somecred@10.203.94.$i:/fbd
done

}

# ---------main() -------------

echoout "I;" "main(): Start $0 with arguments $*"
COMMAND="$1"
##COMMIT="$2"
echoout "I;" "main(): command $COMMAND"
DAT=$(date +%F-%T)
echoout "I;" " using date $DAT in file/folder  names"

## exclude previous errors cause infinite loop

case "$COMMAND" in
"archive")
    p_archive $2
    ;;
"restore")
    p_restore $2
    ;;
"scainstall")
    p_sca_unarchive $2
    ;;
"copyarchive")
    p_copy $2
    ;;
*)
    echoout "E;" "main(): command not suitable : $COMMAND"
    print_usage
    ;;
esac
