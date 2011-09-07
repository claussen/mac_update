#!/bin/bash
###########################
# mac_update.sh
# This script will simplify the OSX updating
#
# USAGE: mac_update.sh
# Example:  mac_update.sh
# Requirements:
#		*  List of FQDN mac hosts in mac_all.txt
#		*  $ADMIN_USER user on remote host
#		*  ssh keys in place with remote host to allow passwordless login as $ADMIN_USER
#
#
#  Suggested Crontab:
#		*  0 */4 * * 1,2,3,4,5  /usr/bin/sudo /usr/sbin/softwareupdate -l  1>/tmp/check_softwareupdate.log 2>&1#
#
#  Suggested /etc/sudoers addition (change $ADMIN_USER as appropriate)
#		#Allow limited softwareupdate actions  w/o password prompt
#		$ADMIN_USER ALL = NOPASSWD: /usr/sbin/softwareupdate -i *
#		#Allow softwareupdate -l  w/o password prompt #required for LION
#		$ADMIN_USER ALL = NOPASSWD: /usr/sbin/softwareupdate -l 
#

# Revisions
# Feb. 25 2011 ver 1.00  Script Creation
# Feb. 27 2011 ver 1.01  added whitelist logic for updates, and add non-whitelist updates to list for consideration
# Feb. 28 2011 ver 1.02  added logic to catch the "Internet offline" issue
# Mar. 22 2011 ver 1.03  now sends e-mail if encountering a new update to consider.
# May. 31 2011 ver 1.04  minor update to update the .$HOST.updates_available log after running.
# Jun. 24 2011 ver 1.05  slight modification to make this site-indepentent.
# Jun. 25 2011 ver 1.06  improvements made to only download update once.
# Jul. 18 2011 ver 1.07  modified to run in cron - no terminal required.
# Jul. 20 2011 ver 1.08  properly handle updates with spaces in the name.  e.g."Migration Assistant Update for Mac OS X Snow Leopard-1.0"
# Jul. 20 2011 ver 1.09  more tweaks for spaces
# Jul. 27 2011 ver 1.09  put space logic in place for .$HOST logs as well.
# Aug. 12 2011 ver 1.10  beginnings of LION support for this script, requires additional SUDOERS entry on all hosts.


# Possible Future Additions
#
#  allow command-line specifing of host to run on - avoid running the whole loop
#  allow command-line specifing of patch to install

#
# Variables
#
###########################
EMAIL_TO_NOTIFY=claussen@conducivetech.com
ADMIN_USER=it_admin
RUN_DIR=/Users/claussen/bin/mac_update
###########################
#
#


# Set the Trap
###########################
LOCKFILE=/tmp/.mac_update_is_running.$USER.lock
if [ -f "$LOCKFILE" ]; then
	echo "lock file exists." $(ls $LOCKFILE)
	exit 5
fi

trap 'rm ${LOCKFILE}' EXIT
(set -C; echo $$ > $LOCKFILE)
###########################
#
#
 

#
# Check to see if mac_all.txt exists
###########################
if [ ! -e $RUN_DIR/mac_all.txt ]; then
	echo "mac_all.txt does not exist"
	echo "Exiting now"
	exit 15
fi
###########################
#
#

#
# Capture IFS - avoid issues with spaces in filenames
###########################
IFS_OLD=$IFS
#Reset IFS to newline - this allows the script to work if there are spaces in an update name.  Apple is *generally* great abou this, but not always.
IFS="$(echo -e "\n\r")"
#IFS=$'\n'
###########################
#
#

for HOST in `cat $RUN_DIR/mac_all.txt`;do
	# Test connectivity to $BACKUP_HOST
	/sbin/ping -c1 -q $HOST > /dev/null
	if [ $? -ne 0 ]; then
		echo "$HOST unreachable - skipping"
        else
		echo "$HOST"
		echo "Running mac_update.sh on  $HOST on `date +%Y-%m-%d-%H-%M-%S`" >> $RUN_DIR/log/$HOST.updates.log
	
		#  confirm /tmp/check_softwareupdate.log exists
		ssh $ADMIN_USER@$HOST  "ls /tmp/check_softwareupdate.log" 1> /dev/null 2>&1
		if [ $? -ne "0" ]; then
			ssh $ADMIN_USER@$HOST  " /usr/bin/sudo /usr/sbin/softwareupdate -l  1>/tmp/check_softwareupdate.log 2>&1"
		fi	

		#  confirm /tmp/check_softwareupdate.log is up to date
		ssh $ADMIN_USER@$HOST  "cat /tmp/check_softwareupdate.log" | grep Internet\ connection\ appears\ to\ be\ offline
		if [ $? -eq "0" ]; then
			echo "time to rerun Software Update"
			ssh $ADMIN_USER@$HOST  " /usr/bin/sudo /usr/sbin/softwareupdate -l  1>/tmp/check_softwareupdate.log 2>&1"
		fi	

		# List updates
		ssh $ADMIN_USER@$HOST  "cat /tmp/check_softwareupdate.log|grep -v '^$' | grep -v No\ new\ software\ available|grep -v Software\ Update\ Tool|grep -v Copyright\ 2002|grep -v Software\ Update\ found\ the\ following\ new\ or\ updated\ software:"

		# Generate list for script
		#ssh $ADMIN_USER@$HOST  "cat /tmp/check_softwareupdate.log" | grep \* | grep -v Missing\ bundle\ identifier | awk  '{ print $2 }' > $RUN_DIR/.$HOST.updates_available
		ssh $ADMIN_USER@$HOST  "cat /tmp/check_softwareupdate.log" | grep \* | grep -v Missing\ bundle\ identifier | sed 's,* ,,g'|sed 's,   ,,g' > $RUN_DIR/.$HOST.updates_available

		if [ -s $RUN_DIR/.$HOST.updates_available ];then
			
			#updates available for host
			IFS="$(echo -e "\n\r")"
			for UPDATE in `cat $RUN_DIR/.$HOST.updates_available` ; do
				#Is update allowed?
				grep "$UPDATE" $RUN_DIR/allowed_updates.txt > /dev/null
				if [ $? -eq "0" ]; then
					echo "Installing $UPDATE on $HOST"
					echo "Installing $UPDATE on $HOST on `date +%Y-%m-%d-%H-%M-%S`" >> $RUN_DIR/log/$HOST.updates.log
					ssh -t $ADMIN_USER@$HOST "sudo softwareupdate -i \"$UPDATE\"" 1>>$RUN_DIR/log/$HOST.updates.log 2>&1
				else
					grep "$UPDATE" $RUN_DIR/log/$HOST.updates.log > /dev/null
					if [ $? -eq "1" ]; then	
						# download the update, but do not install - makes it faster for the user to install later
						echo "Downloading  $UPDATE on $HOST on `date +%Y-%m-%d-%H-%M-%S`" >> $RUN_DIR/log/$HOST.updates.log
						ssh $ADMIN_USER@$HOST "softwareupdate -d \"$UPDATE\"" 1>>$RUN_DIR/log/$HOST.updates.log 2>&1
						grep "$UPDATE" $RUN_DIR/updates_to_consider.txt > /dev/null
						if [ $? -eq "0" ]; then
							echo "$UPDATE already on the condsideration list"
						else
							echo "adding $UPDATE to list for consideration"
							echo "$UPDATE" >> updates_to_consider.txt	
							echo "$UPDATE" | mail -s "Mac_Update - new update to consider" $EMAIL_TO_NOTIFY
						fi
					else
						echo "$UPDATE already downloaded - skipping"
					fi
				fi
			done
			#update /tmp/check_softwareupdate.log
			ssh $ADMIN_USER@$HOST "/usr/bin/sudo /usr/sbin/softwareupdate -l  1>/tmp/check_softwareupdate.log 2>&1"
		
			# update log
			#ssh $ADMIN_USER@$HOST  "cat /tmp/check_softwareupdate.log" | grep \* | grep -v Missing\ bundle\ identifier | awk  '{ print $2 }' > $RUN_DIR/.$HOST.updates_available
			ssh $ADMIN_USER@$HOST  "cat /tmp/check_softwareupdate.log" | grep \* | grep -v Missing\ bundle\ identifier | sed 's,* ,,g'|sed 's,   ,,g' > $RUN_DIR/.$HOST.updates_available
		fi       
	fi
done
###########################
#
#

#reset IFS to old value
IFS=$IFS_OLD
