#!/bin/bash
#
# Aerospike Backup Tool
# Copyright (c) 2018 Alexey Baikov <sysboss[@]mail.ru>
#
# Description: Backing up Aerospike to S3 Bucket
# GitHub: https://github.com/sysboss/aerospike_backup

##########################
# Required Configuration #
##########################
WORKDIR="/mnt"
BACKUP_DIR="${WORKDIR}/backups"

# Backup behavior
  STORE_LOCAL_COPIES=0
  S3_BUCKET_NAME=""
  # Year/Mon/Day/HostName
  INSTANCE_NAME=`hostname`
  S3_BUCKET_PATH=`date +'%Y'`"/"`date +'%b'`"/"`date +'%d'`/${INSTANCE_NAME}

# Other defaults
  FILE_NAME_FORMAT="aerospike_"`date '+%F-%H%M'`".asb.gz"
  LOCKFILE="${WORKDIR}/.as-backup.lock"
  LOGFILE="${WORKDIR}/as-backup.log"
  LOGTOFILE="false"
  REQUIRED_TOOLS="asbackup aws tar"

##########################
# Functions              #
##########################
function usage {
cat << EOF
Aerospike Backup Tool
Copyright (c) 2018 Alexey Baikov <sysboss[@]mail.ru>
usage: $0 options

OPTIONS:
    -a    Aerospike namespace to backup
    -b    AWS S3 Bucket Name
    -w    Work directory path (default: /mnt)
    -l    Log to file (default: STDOUT)
    -k    Keep local copies (default: 0)
    -r    AWS S3 Region (optional)
    -p    Path / Folder inside the bucket (optional)
EOF
}

while getopts ":l:h:w:k:b:a:p:" OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    w)
      WORKDIR=$OPTARG
      ;;
    l)
      LOGTOFILE="true"
      ;;
    k)
      STORE_LOCAL_COPIES=$OPTARG
      ;;
    r)
      S3_REGION=$OPTARG
      ;;
    b)
      S3_BUCKET_NAME=$OPTARG
      ;;
    p)
      S3_BUCKET_PATH=$OPTARG
      ;;
    a)
      AEROSPIKE_NAMESPACE=$OPTARG
      ;;
    ?)
      usage
      exit
    ;;
  esac
done


# options
if [[ -z ${AEROSPIKE_NAMESPACE} || -z ${WORKDIR} || -z ${STORE_LOCAL_COPIES} || -z ${S3_BUCKET_NAME} ]]; then
    usage
    exit 1
fi

function die {
    echo $@
    exit 126
}

function lock {
    LOCK_FD=2
    local fd=${200:-$LOCK_FD}

    # create lock file
    eval "exec $fd>$LOCKFILE"

    # acquier the lock
    flock -n $fd \
        && return 0 \
        || return 1
}

function unlock {
    rm -f $LOCKFILE
}

function getDateTime {
    echo $(date '+%Y-%m-%d %H:%M:%S')
}

function logToFile {
    exec > $LOGFILE
    exec 2>&1
}

function log {
    local msg=$1
    local lvl=${2:-"INFO"}

    if ! which printf > /dev/null; then
        echo "$(getDateTime)  $lvl  $msg" #| tee -a ${LOGFILE}
    else
        printf "%15s  %5s  %s\n" "$(getDateTime)" "$lvl" "$msg"
    fi
}

function cleanup {
    local lvl=$1

    # release lock
    unlock

    # rotate backups
    COUNT="$(ls -tp ${BACKUP_DIR}/aerospike_*.gz | wc -w)"
    DELETE=$(($COUNT-$STORE_LOCAL_COPIES))

    log "Cleanup: Found ${COUNT} backups. ${DELETE} copies will be deleted"

    # remove old backups
    if [ $DELETE -ge 0 ]; then
        ls -lat ${BACKUP_DIR}//aerospike_*.gz | \
          tail -$DELETE | awk '{print $NF}' | \
          xargs rm -f
    fi

    # report, on error/abortion
    if [ "$lvl" != "" ]; then
        # remove currupted backup file
        if [ -f "${DUMPFILE}" ]; then
            log "Removing currupted backup file: ${DUMPFILE}" "ERROR"
            rm -f "${DUMPFILE}"
        fi

        log "Aborting backup" "$lvl"
        exit 2
    fi
}

function runCommand {
    "$@"
    exitCode=$?

    if [ $exitCode -ne 0 ]; then
        log "Failed to execute: $1 command ($exitCode)" "ERROR"
        cleanup "ERROR"
        exit 2
    fi
}

# setup trap function
function sigHandler {
    if type cleanup | grep -i function > /dev/null; then
        trap "cleanup KILL" HUP TERM INT
    else
        echo "ERROR: cleanup function is not defined"
        exit 127
    fi
}

# Create directories and files
mkdir -p "${BACKUP_DIR}"
[ "${LOGTOFILE}" == "true" ] && touch ${LOGFILE}

# verify no other backup is running
lock || die "Only one backup instance can run at a time"

# interrupts handler
sigHandler

# log to file
[ "${LOGTOFILE}" == "true" ] && logToFile

# verify all tools installed
for i in ${REQUIRED_TOOLS}; do
    if ! which $i > /dev/null; then
        die "ERROR: $i is required."
    fi
done

# log start time
log "Starting Aerospike Backup (Namespace: ${AEROSPIKE_NAMESPACE})"

log "Taking database dump into backup directory"
DUMPFILE="${BACKUP_DIR}/${FILE_NAME_FORMAT}"

runCommand asbackup --namespace ${AEROSPIKE_NAMESPACE} --output-file - | gzip -1 > ${DUMPFILE}

log "Uploading to S3 Bucket (s3://${S3_BUCKET_NAME}/${S3_BUCKET_PATH})"
runCommand aws s3 cp ${DUMPFILE} s3://${S3_BUCKET_NAME}/${S3_BUCKET_PATH}/${FILE_NAME_FORMAT}

# do some cleanup
# and release locks
cleanup

log "Backup complete"
