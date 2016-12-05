#!/usr/bin/env bash
# ------------------------------------------ #
# File : sambaBackup.sh
# Author : Juri Calleri
# Email : juri@juricalleri.net
# Date : 27/04/2016
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
# This script will create a backup of one or more main folder(s) (it depends how cron calls it)
# It will archive, encrypt (you need your own certificate) and delete if older than x days.
# Supports Nagios if used with my check_backup_status.sh script
# ------------------------------------------ #
# Usage: 
# 1.
#  Cron calls the script every 4AM of Saturday:
#   00 04 * * 6 /home/user/scripts/samba/sambaBackup.sh /home/samba /home/user/scripts/samba/current /nfsbackup/samba_backup/current/samba
# 2.
#   The script process folders inside $1 (/home/samba)
#   Listed in the file $2 (/home/user/scripts/samba/current)
#   And will save the result in $3 /nfsbackup/samba_backup/current/samba
#
# If happens to be more folders to backup, such as:
# /home/samba/
# /home/user/
# /home/user2/projects
#
# 1.
#   Cron calls the main script every 4AM of Saturday:
#   00 04 * * 6 /home/user/scripts/samba/startSambaBackup.sh
#
# Whose content is:
#  _______________________________________________________________________________________________
# | #!/usr/bin/env bash
# |
# | PWD=/home/myuser/scripts/samba/
# | CURRENT=${PWD}/current
# | user_backup_folders=${PWD}/user_backup_folders
# | projects_2_backup=${PWD}/projects_2_backup
# |
# | ${PWD}/sambaBackup.sh /home/samba/ ${CURRENT} /nfsbackup/samba_backup/current
# | sleep 30
# | ${PWD}/sambaBackup.sh /home/user/ ${user_backup_folders} /nfsbackup/user
# | sleep 30
# | ${PWD}/sambaBackup.sh /home/user2/projects ${projects_2_backup} /nfsbackup/projects_backup
# |_______________________________________________________________________________________________
# ------------------------------------------ #
# AND
# $1 = path of folder to backup => backup/samba_backup/current
# $2 = list.txt with name of folders to backup**
# $3 = Destination folder => /nfsbackup/samba_backup/
#
# **Note:
# $2 -> $LIST => A txt file with row-by-row the name of the folder to backup:
# Like:
#  _______________________
# | university
# | pictures
# | importantDocuments
# |______________________
# 
# Name format:
# ${TODAY}_${ROW}.dat
#
# You'll notice I refer to a ftp path, or something mounted as RO.
# It depends if the destination folder is a shared folder or not.
# Mine is, with nfs filesystem. Therefore I applied some tricks when, for weird reasons,
# the share is not accessible or RO mounted (don't ask me why).

TOSAVE=$1
PLIST=$2
DESTF=$3

LIST=$(echo ${PLIST} | awk 'BEGIN{FS="/"}{print $NF}') # Cut whole path from $2
TODAY=$(date +%d%m%y)
TIME=$(date +%c)
KEY="/home/myuser/scripts/samba/enc" #you'll need to create your own certificate to encrypt your backup
ERROR="/backup/samba_backup/ERROR" #if destination folder is not accessible
MAIL="/tmp/mail_${LIST}.log" #will be used with check_backup_status.sh and Nagios
FTPDEL="/tmp/delete_${LIST}"

LOG2=""
FLOG="/var/log/${LIST}.log"
RING=0 
# RING is a +1 token for every command completed correctly, 7 in total
# In case of errors, RING will be "99" and the current ROW skipped

# uncomment below to debug code during execution
#set -x
umask 000

cd ${TOSAVE}
>${FLOG} # flush log
echo -e "${TIME} \n" >> ${FLOG}
while read ROW
do

  tar -cf ${ROW}.tar ${ROW} 2>&1
  if [ $? -eq 0 ]; then
    echo -e "Taring ${ROW}: OK" >> ${FLOG}
    ((RING+=1)) # +1
  else
    echo -e "Error while taring ${ROW}" >> ${FLOG}
    RING=99
  fi

  sha256sum ${ROW}.tar > ${ROW}.checksum 2>&1
  if [[ $? -eq 0 && $RING -ne 99 ]]; then
    echo -e "Checksum ${ROW}: OK" >> ${FLOG}
    ((RING+=1)) # +2
  else
    echo -e "Error while creating checksum for ${ROW}.tar" >> ${FLOG}
    RING=99
  fi

  sleep 60
  lbzip2 -k -n2 -1 ${ROW}.tar 2>&1
  if [[ $? -eq 0 && $RING -ne 99 ]]; then
    echo -e "Compressing ${ROW}: OK" >> ${FLOG}
    ((RING+=1)) # +3 
  else
    echo -e "Error while creating bz2 for ${ROW}.tar" >> ${FLOG}
    RING=99
  fi

  [[ -f ${ROW}.tar ]] && rm -f ${ROW}.tar
  sleep 60
  lbzip2 -d -n2 -k ${ROW}.tar.bz2 2>&1
  if [[ $? -eq 0 && $RING -ne 99 ]]; then
    echo -e "De-compressing ${ROW}: OK" >> ${FLOG}
    ((RING+=1)) # +4
  else
    echo -e "Error while decompressing ${ROW}.tar.bz2" >> ${FLOG}
    RING=99
  fi

  sleep 90
  sha256sum -c -- ${ROW}.checksum 2>&1
  if [[ $? -eq 0 && $RING -ne 99 ]]; then
    echo -e "Check checksum ${ROW}: OK" >> ${FLOG}
    ((RING+=1)) # +5
  else
    echo -e "Error checksum wrong for ${ROW}.tar" >> ${FLOG}
    RING=99
  fi

  # you know...
  if [ $RING -eq 5 ]; then
    openssl enc -aes-256-cbc -pass pass:$(openssl rsautl -decrypt -inkey ${KEY}/backups.pem -in ${KEY}/enc.cry) -in ${ROW}.tar.bz2 -out ${TODAY}_${ROW}.dat 2>&1
    if [ $? -eq 0 ]; then
      rm -f "${TODAY}_${ROW}.tar.bz2" 2>&1
      echo -e "Encrypting ${ROW}.tar.bz2: OK" >> ${FLOG}
      ((RING+=1)) # +6
    else
      echo -e "Error encrypting ${ROW}.tar.bz2" >> ${FLOG}
	  [[ -f ${ROW}.tar.bz2 ]] && rm -f ${ROW}.tar.bz2
      RING=99
    fi
  else
    echo -e "Error processing ${ROW}" >> ${FLOG}
	echo -e "Skipping encryption for ${ROW}" >> ${FLOG}
    RING=99
  fi

  sleep 30
  # Deleting traces and moving backups to ftp drive
  [[ -f ${ROW}.tar.bz2 ]] && rm -f ${ROW}.tar.bz2
  [[ -f ${ROW}.checksum ]] && rm -f ${ROW}.checksum
  [[ -f ${ROW}.tar ]] && rm -f ${ROW}.tar
  
  if [ $RING -eq 99 ]; then
    echo -e "Due to previous Errors I can not process this transfer" >> ${FLOG}
  else
    cp "${TODAY}_${ROW}.dat" "${DESTF}/" 2>&1
	if [ $? -eq 0 ]; then
	  echo -e "Moving ${TODAY}_${ROW}.dat to ${DESTF}: OK" >> ${FLOG}
	  ((RING+=1)) # +7
	  rm -r "${TODAY}_${ROW}.dat"
	else
	  echo -e "Error moving ${TODAY}_${ROW}.dat to ${DESTF} - Trying moving to $ERROR/$LIST..." >> ${FLOG}
      [ -d "$ERROR/$LIST" ] || mkdir -p "$ERROR/$LIST"
      cp "${TODAY}_${ROW}.dat" "${ERROR}/$LIST" 2>&1
      if [ $? -eq 0 ]; then
        echo -e "${ROW}.dat copied to $ERROR/$LIST folder instead" >> ${FLOG}
        echo -e "Probably /nfsbackup/ is RO mounted - run \"umount /nfsbackup\" and \"mount -a\" to remount the drive" >> ${FLOG}
        rm -r "${TODAY}_${ROW}.dat"
		RING=8
	  else
	    echo -e "Could not move ${ROW}.dat to $ERROR/$LIST" >> ${FLOG}
		RING=9
      fi
    fi
  fi

  # Write log and reset
  if [ $RING -eq 7 ]; then
    LOG2+="${ROW}: \tProcessed correctly\n"
  fi
  if [ $RING -eq 8 ]; then
    LOG2+="${ROW}: \tProcessed with warning - ${ROW}.dat copied to $ERROR/$LIST folder\n"
  fi
  if [ $RING -ge 9 ]; then
    LOG2+="${ROW}: \tProcessed with error\n"
  fi
  RING=0
  echo -e "" >> ${FLOG}
done <${PLIST}
# End of while cicle

sleep 30
# Find backups older than 3 months and delete them
find ${DESTF} -maxdepth 1 -type f -mtime +90 -printf "%f\n" > ${FTPDEL}
sleep 3
if [[ $? -eq 0 && $(wc -l <${FTPDEL}) -gt 0 ]]; then
  cd ${DESTF}
  xargs -a ${FTPDEL} rm -r
  echo -e "\nBackups older than 3 months have been deleted" >> ${FLOG}
else
  echo -e "\nNo Backups older than 3 months" >> ${FLOG}
fi

# Time to result log
echo -e "\nResults of ${TIME}:" >> ${FLOG}
echo -e "Read the log in ${FLOG} for more details\n" >> ${FLOG}
echo -e ${LOG2} >> ${FLOG}

# It would be great to have the log emailed
>${MAIL} # flush mail log
cat ${FLOG} | sed '1,/Results of/d' >> ${MAIL}
