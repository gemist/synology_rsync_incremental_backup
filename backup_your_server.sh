#!/bin/bash

#
# start script using crontab from synology
# authorized_keys have to be set in order to access server from synology
# author: https://github.com/gemist/
#

#start time
echo "--------------------------------------------------------------------------"
echo "starting your_server backup: `date`"

starttime0=`date +%s`

#INCREMENTAL BACKUP

#select folders for incremental backup
FOLDER_LIST[0]="/home"
FOLDER_LIST[1]="/data/shift"
FOLDER_LIST[2]="/opt"
FOLDER_LIST[3]="/var/www"
FOLDER_LIST[4]="/etc"
#name of server
SERVER="root@192.168.1.1" # or "root@yourdomain.com" 
# specify destination path
DT_PATH="/volume1/NetBackup/yourserver-backup/incremental_backup"

mkdir -p ${DT_PATH}

#in case you want to use logs 
mkdir -p $HOME/scripts/logs
# find the last cronological backup on your Synology)
LAST_BACKUP_PATH=$(find ${DT_PATH} -mindepth 1 -maxdepth 1 -type d | sort | tail -1)

#create NEW_BACKUP folder
DATE=`date +%Y-%m-%d_%H-%M-%S`
NEW_BACKUP="${DT_PATH}/${DATE}"

mkdir -p ${NEW_BACKUP}

for f in "${FOLDER_LIST[@]}"
do
    starttime=`date +%s`	
	bn=`basename ${f}`
	# synology rsync "sometimes" does not support -A option, workaround to get facl permissions 
	ssh $SERVER "cd ${f}; ionice -c3 nice -n 19 getfacl -R -s *" | gzip -c > ${NEW_BACKUP}/${bn}_ACL.gz
	#check if On DataTron (Synology)  is already backup
	if [ ! -z "${LAST_BACKUP_PATH}" ]; then
	    #	echo "Found last backup at ${LAST_BACKUP_PATH}"
	    echo -e "\n*) Backup ${bn}..."
		#copy hard links from old destination
		if [ -d "${LAST_BACKUP_PATH}/${bn}" ]; then
		    cp -al ${LAST_BACKUP_PATH}/${bn} ${NEW_BACKUP}
		fi
		rsync -aHX --stats -h --numeric-ids --delete --exclude='backup/rootsnapshot' --exclude='backup/gitlab' \
		      -e "ssh -T -c aes128-ctr -o Compression=no -x" ${SERVER}:${f} ${NEW_BACKUP}
	else 
	    #	echo "First time backup"
	    echo -e "\n*) Backup ${bn}..."
	    rsync -aHX --stats -h --numeric-ids --exclude='backup/rootsnapshot' --exclude='backup/gitlab' \
		  -e "ssh -T -c aes128-ctr -o Compression=no -x" ${SERVER}:${f} ${NEW_BACKUP}
	fi
	endtime=`date +%s`
	runtime=$(($endtime-$starttime))
	echo -e "\nElapsed time for ${bn}: $(($runtime / 3600))hrs $((($runtime/60) % 60))min $(($runtime % 60))sec"
done


#NON INCREMENTAL BACKUP

# a) GITLAB BACKUP

starttime=`date +%s`
#specify gitlab source and destionation paths
GITLAB_SOURCE_PATH="/data/shift/backup/gitlab/"
GITLAB_DT_FOLDER="/volume1/NetBackup/yourserver-backup/gitlab"

mkdir -p ${GITLAB_DT_FOLDER}
echo -e "\n*) Backup gitlab..."
rsync -aHX --ignore-existing --stats -h --numeric-ids -e "ssh -T -c aes128-ctr -o Compression=no -x" ${SERVER}:${GITLAB_SOURCE_PATH} ${GITLAB_DT_FOLDER}

#check if GITLAB_DT_FOLDER exist
if [ -d "${GITLAB_DT_FOLDER}" ]; then
    #delete gitlab files older than 30 days
    find ${GITLAB_DT_FOLDER} -mtime +30 -type f -delete 
fi
endtime=`date +%s`
runtime=$(($endtime-$starttime))
echo -e "\nElapsed time for gitlab: $(($runtime / 3600))hrs $((($runtime/60) % 60))min $(($runtime % 60))sec"


# b) LVM FILESYSTEM BACKUP

starttime=`date +%s`
DT_PATH="/data/shift/backup/rootsnapshot/"
LVM_DT_FOLDER="/volume1/NetBackup/yourserver-backup/lvm-snapshot"

mkdir -p ${LVM_DT_FOLDER}
echo -e "\n*) Backup lvm-snapshot..."
rsync -aHX --ignore-existing --stats -h --exclude='logs'  --numeric-ids -e "ssh -T -c aes128-ctr -o Compression=no -x" ${SERVER}:${DT_PATH} ${LVM_DT_FOLDER}

#check if LVM_DT_FOLDER exist
if [ -d "${LVM_DT_FOLDER}" ]; then
    #delete LVM files older than 60 days 
    find ${LVM_DT_FOLDER} -mtime +60 -type f -delete
fi

endtime=`date +%s`
runtime=$(($endtime-$starttime))
echo -e "\nElapsed time for lvm-snapshot: $(($runtime / 3600))hrs $((($runtime/60) % 60))min $(($runtime % 60))sec"


# total time
endtime=`date +%s`
runtime=$(($endtime-$starttime0))
echo -e "\nTotal elapsed time: $(($runtime / 3600))hrs $((($runtime/60) % 60))min $(($runtime % 60))sec"

