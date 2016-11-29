#!/usr/bin/env bash
#
# ------------------------------------------ #
# File : cleanup.sh
# Author : Juri Calleri
# Email : juri@juricalleri.net
# Date : 14/06/2016
# ------------------------------------------ #
# This program is free software; you can redistribute it and/or modify it
# without even asking for permission, but please keep the author.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ------------------------------------------ #
# What do I need this for?
# If you need to backup the content of a folder, everyday..
# And copy in a backup folder names as the day of the year sequentially..
# And delete the file in the source folder to make place for new ones..
# This script will do the job.
# ------------------------------------------ #
# Usage: 
# This script is called by CRON and will run at 23:55 every day.
# It will copy yesterday's files inside $TODAY-1 folder.
# It will delete those file if copy went successful.
# It will seek the backup folder older than 180 days and will delete.
#
# 1.
#    Edit crontab (crontab -e) and add:
#    55 23 * * * /home/user/scripts/cleanup.sh
#
# $BDIR(/backup/)
# |    |__data_quit_backup/$TODAY-1
# |
# $HOME
# |
# |____Script
# |          |__cleanup.sh
# |____Data
#          |__The file to process
#
# ------------------------------------------ #
# Nagios/Unix Exit codes
# OK=0
# WARNING=1
# CRITICAL=2
# UNKNOWN=3


export PATH=$PATH:/bin:/usr/bin:/usr/local/bin

# directory to backup
HOME=/home/user
MYBACKUP="my Backup" # Give a name to your backup
TOSAVE=$HOME/data
TODAY=$(date "+%F" -d "1 day ago")
BDIR=/backup/${MYBACKUP}
BACKUPDIR=$BDIR/$TODAY
LIST=$HOME/toCopy
FDEL=$HOME/foldersToDelete
FLOG="/var/log/$MYBACKUP.log"

# options for rsync
OPTS="-aq --files-from=$LIST"

# MAIN #
# find yesterday's new files
# -daystart -mtime 0 
# If there are folders to exlude use this command accordingly
# find $TOSAVE -mindepth 1 -daystart -mtime +0 -type f -not -path "*.procmail*" -not -path "*scripts*" -not -path "*scripts/backup*" -printf "%f\n" > $LIST
find $TOSAVE -mindepth 1 -daystart -mtime +0 -type f -printf "%f\n" > $LIST

if [[ $? -eq 0 && $(wc -c <"$LIST") -gt 0 ]]; then
# copy daily found inside new created daily folder
  [ -d $BACKUPDIR ] || mkdir -p $BACKUPDIR
  rsync $OPTS $TOSAVE $BACKUPDIR
  if [ $? -eq 0 ]; then
    cd $TOSAVE
    xargs -d '\n' -a $LIST rm
    LOG="${MYBACKUP} backup for $TODAY: OK"
  else 
    LOG="RSYNC: There was an error processing the backup of ${MYBACKUP} for $TODAY"
  fi
else
  if [ $(wc -c <"$LIST") -gt 0 ]; then
# create an error log if LIST has records inside but the backup went unsuccessful 
    LOG="FIND: There was an error creating the ${MYBACKUP} backup LIST of $TODAY"
  fi
  if [ $(wc -c <"$LIST") -eq 0 ]; then
    LOG="There is no ${MYBACKUP} backup for $TODAY"
  fi
fi
rm $LIST
# delete backup folder older than 180+ days
#find ${BDIR} -type d -mtime +180 -print0 | xargs -0 -r rm -rf
find ${BDIR} -type d -mtime +180 -printf "%f\n" > $FDEL
if [[ $? -eq 0 && $(wc -l <"$FDEL") -gt 0 ]]; then
    cd ${BDIR}
    xargs -d '\n' -a $FDEL rmdir
  LOG+=" - Folders older than 180 days have been deleted"
  echo ${LOG} >> ${FLOG}
else
  LOG+=" - No folders older than 180 days have been deleted"
  echo ${LOG} >> ${FLOG}
fi
rm $FDEL
