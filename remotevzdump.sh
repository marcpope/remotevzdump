#!/bin/bash

#remotevzdump by Marc Pope
#modified version of ezvzdump to skip the local copy first, saving space

#notice: this software has no guarantees. use at own risk
#you must already have ssh keys installed in the root of the remote server
#to install a ssh key, run ssh-copy-id root@yourserverip
#if you dont already have a public key, run ssh-keygen first

VEIDS="101 102 103"

VZ_CONF="/etc/vz/conf/"             # the path to your openvz $VEID.conf files
VZ_PRIVATE="/vz/private/"           # the path to the running VE's
LOCAL_DIR="/vz/remotevzdump/"           # the local rsync cache / destination directory

# The remote host and path that this script will rsync the VE's to.
REMOTE_HOST="192.168.10.1"
REMOTE_DIR="/home/backups/"

# Default rsync flags (please note the potentially unsafe delete flags).
# You can also remove the v flag to get less verbose logging.
RSYNC_DEFAULT="rsync -ravH --delete-after --delete-excluded"

# Exclude these directories from backup (space delimited).
# I left /var/log in the backup because when doing a full restore
# it's necessary that this directory structure is present.
RSYNC_EXCLUDE="/usr/portage"

# Path to vzctl executable
VZCTL="vzctl"

# Nice debugging messages...
function e {
  echo -e $(date "+%F %T"):  $1
}
function die {
  e "Error: $1" >&2
  exit 1;
}

# Make sure all is sane
[ ! -d "${VZ_CONF}" ]    && die "\$VZ_CONF directory doesn't exist. ($VZ_CONF)"
[ ! -d "${VZ_PRIVATE}" ] && die "\$VZ_PRIVATE directory doesn't exist. ($VZ_PRIVATE)"

e "`hostname` - VZ backup for containers $VEIDS started." > /tmp/vzbackuptimes
# Loop through each VEID
for VEID in $VEIDS; do

  VEHOSTNAME=`vzlist -o hostname $VEID -H`
  echo ""
  e "Beginning backup of VEID: $VEID";

  # Build up the --exclude string for the rsync command
  RSYNC="${RSYNC_DEFAULT}"
  for path in $RSYNC_EXCLUDE; do
    RSYNC+=" --exclude=${VEID}${path}"
  done;

  RSYNCCOMMAND="${RSYNC} ${VZ_PRIVATE}${VEID} root@${REMOTE_HOST}:${REMOTE_DIR}"
  e "Commencing initial $RSYNCCOMMAND"
  $RSYNCCOMMAND


  # If the VE is running, suspend, re-rsync and then resume it ...
  if [ -n "$(${VZCTL} status ${VEID} | grep running)" ]; then

    e "Suspending VEID: $VEID"
    before="$(date +%s)"
    ${VZCTL} chkpnt $VEID --suspend

    e "Commencing second pass rsync ..."
    $RSYNCCOMMAND

    e "Resuming VEID: $VEID"
    ${VZCTL} chkpnt $VEID --resume
    after="$(date +%s)"
    elapsed_seconds="$(expr $after - $before)"

    e "Done."
    e "Container ${VEID} ($VEHOSTNAME) was down $elapsed_seconds seconds during backup process." >> /tmp/vzbackuptimes

  else
    e "# # # Skipping suspend/re-rsync/resume, as the VEID: ${VEID} is not curently running."
  fi


e "Make directory if not exists for VZ Config..."
  mkdir -p ${LOCAL_DIR}${VEID}/etc/vzdump


  e "Copying main config file: cp ${VZ_CONF}${VEID}.conf ${LOCAL_DIR}${VEID}/etc/vzdump/vps.conf"
  [ ! -f "${VZ_CONF}${VEID}.conf" ] && die "Unable to find ${VZ_CONF}${VEID}.conf"
  cp ${VZ_CONF}${VEID}.conf ${LOCAL_DIR}${VEID}/etc/vzdump/vps.conf

  for ext in start stop mount umount; do
    if [ -f "${VZ_CONF}${VEID}.${ext}" ]; then
      e "Copying other config file: cp ${VZ_CONF}${VEID}.${ext} ${LOCAL_DIR}${VEID}/etc/vzdump/vps.${ext}"
      cp ${VZ_CONF}${VEID}.${ext} ${LOCAL_DIR}${VEID}/etc/vzdump/vps.${ext}
    fi
  done;

  # Run the remote rsync
  if [ -n "${REMOTE_HOST}" ] && [ -n "${REMOTE_DIR}" ]; then
    e "Remote rsync of config files to remote server..."
    rsync -avz ${LOCAL_DIR}${VEID}/ root@${REMOTE_HOST}:${REMOTE_DIR}${VEID}/

    # Rotate older tar.gz backups if they exist. You can comment out these lines if you wish to have only one copy.
    e "Checking for existing files ${REMOTE_HOST}:${REMOTE_DIR}${VEID}.X.tar and rotating them"
    ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${VEID}.6.tar.gz ] && mv -f ${REMOTE_DIR}${VEID}.6.tar.gz ${REMOTE_DIR}${VEID}.7.tar.gz"
    ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${VEID}.5.tar.gz ] && mv -f ${REMOTE_DIR}${VEID}.5.tar.gz ${REMOTE_DIR}${VEID}.6.tar.gz"
    ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${VEID}.4.tar.gz ] && mv -f ${REMOTE_DIR}${VEID}.4.tar.gz ${REMOTE_DIR}${VEID}.5.tar.gz"
    ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${VEID}.3.tar.gz ] && mv -f ${REMOTE_DIR}${VEID}.3.tar.gz ${REMOTE_DIR}${VEID}.4.tar.gz"
    ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${VEID}.2.tar.gz ] && mv -f ${REMOTE_DIR}${VEID}.2.tar.gz ${REMOTE_DIR}${VEID}.3.tar.gz"
    ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${VEID}.1.tar.gz ] && mv -f ${REMOTE_DIR}${VEID}.1.tar.gz ${REMOTE_DIR}${VEID}.2.tar.gz"
    ssh ${REMOTE_HOST} "[ -f ${REMOTE_DIR}${VEID}.0.tar.gz ] && mv -f ${REMOTE_DIR}${VEID}.0.tar.gz ${REMOTE_DIR}${VEID}.1.tar.gz"

    # Create a remote tar archive - note you can remove the ampersand from the end if you
    # don't want multiple tar processes running on the remote host simultaneously.
    e "Making a g-zip compresssed tar archive on remote host (this process will run in the background on the remote host)."
    ssh ${REMOTE_HOST} "tar czf ${REMOTE_DIR}${VEID}.0.tar.gz --numeric-owner -C ${REMOTE_DIR}${VEID} ./ 2>/dev/null " &
  fi

  e "Done."
done;

e "`hostname` - VZ backup for containers $VEIDS complete!" >> /tmp/vzbackuptimes
# Email a log of the backup process to some email address. Can be modified slightly to use native "mail" command
# if sendmail is installed and configured locally.
#cat /tmp/vzbackuptimes | sendEmail -f root@`hostname` -t someuser@example.com -u "`hostname` VZ backup statistics." -s mail.example.com #(put your open relay here)
echo
cat /tmp/vzbackuptimes
rm /tmp/vzbackuptimes
