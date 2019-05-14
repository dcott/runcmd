#!/bin/bash

# The runcmd.sh script is used to execute a shell command on large numbers
# systems via ssh. Commands are run in in parallel and output is redirected
# to a separate log file for each host.
# 
# Public key authentication should be configured for your account on each
# host. The ssh command uses BatchMode and disables StrictHostKeyChecking
# to make things a bit more seemless. See ssh_config(5) for more details.
# 
# Check 'runcmd.sh' -h for usage

# CONFIG VARS
LOGDIR="$HOME/.runcmd"

# A Usage message to be printed on error or when user asks for help
USAGE="USAGE: [HOSTS='host1 host2 ...'] `basename $0` [hkqs] [-u <USERNAME>] [-f <filename> | <'hostname[{001..010}]  ...'> ] -c 'command string'\n"
USAGE=${USAGE}'\t-h prints this message\n'
USAGE=${USAGE}'\t-q do not print remote command output to console\n'
USAGE=${USAGE}'\t-u specify remote username\n'
USAGE=${USAGE}'\t-f filename or hostlist with optional brace expansion\n'
USAGE=${USAGE}'\t-k runs ssh-copy-id for all hosts, you will be prompted for a password\n'
USAGE=${USAGE}'\t-p run remote command with sshpass, you will be prompted for a password\n'
USAGE=${USAGE}'\t-s run remote command with sudo, you will be prompted for a password\n'
USAGE=${USAGE}'\t-c the command to run on each host, required for all but -k\n'

pidList="";
function handleSigInt() {
	for pid in $pidList; do
		kill $pid > /dev/null 2>&1;
	done
	exit;
}

trap handleSigInt INT

if ! [ -d "$LOGDIR" ]; then
	mkdir -p "$LOGDIR";
	if [ $? != 0 ]; then
		echo "Failed to create logdir: '$LOGDIR'";
		exit 1;
	fi
fi

QUIET=FALSE
CMD=FALSE
FILE=FALSE
COPYID=FALSE
ENABLE_SUDO=FALSE
ENABLE_SSHPASS=FALSE
while getopts c:f:hkpqsu: OPTION; do
	case $OPTION in
		(c)
			CMD=TRUE
			COMMAND=$OPTARG
			;;
		(f)
			FILE=TRUE
			HOST_FILE=$OPTARG
			;;
		(h)
			echo -en $USAGE
			exit 0
			;;
		(k)
			COPYID=TRUE
			;;
		(q)
			QUIET=TRUE
			;;
		(p)
			ENABLE_SSHPASS=TRUE
			;;
		(s)
			ENABLE_SUDO=TRUE
			;;
		(u)
			USER=$OPTARG
			;;
	esac
done

which sshpass > /dev/null 2>&1
SSHPASS_RC="$?"
if [ "$COPYID" == "TRUE" -a "$SSHPASS_RC" != "0" ]; then
	echo "-k requires sshpass to be installed";
	exit 1
fi
if [ "$ENABLE_SSHPASS" == "TRUE" -a "$SSHPASS_RC" != "0" ]; then
	echo "-p requires sshpass to be installed";
	exit 1
fi

# Make sure the user gave a command if we're not just running ssh-copy-id
if [ "$COPYID" == "FALSE" -a "$CMD" != "TRUE" ]; then
	echo -en $USAGE
	exit 1
fi

# Setup Logging
TIMESTAMP=`date '+%Y_%m_%d_%H_%M_%S'`;
LOGDIR="$LOGDIR/$TIMESTAMP";
FAILED_HOSTS="$LOGDIR/FAILED_HOSTS";
if ! mkdir -p $LOGDIR; then
	echo "### ERROR: Unable to create log dir '$LOGDIR'";
	exit 1;
fi

if ! echo "$COMMAND" > "$LOGDIR/COMMAND"; then
	echo "### ERROR: Unable to create COMMAND log file.";
	exit 1;
fi

# Read in a list of hosts
if [ $FILE == TRUE ]; then
	if [ -r "$HOST_FILE" ]; then
		source "$HOST_FILE"
	else
		for arg in $HOST_FILE; do
			HOSTS="$HOSTS `eval echo $arg`"
		done
	fi
else
	if [ "$HOSTS" == "" ]; then
		echo -en $USAGE
		exit 0
	fi
fi

function get_pw() {
	read -s -p "${USER}'s password: " PW;
	echo "";
}

function ssh_copy_id() {
	get_pw

	for HOST in $HOSTS; do
		sshpass ssh-copy-id ${USER}@${HOST} <<<"$PW" >> "$LOGDIR/$HOST" 2>&1 &
		hosts[$!]="$HOST";
		pidList="$pidList $!";
	done
}

function exec_remote_command() {
	for HOST in $HOSTS; do
		ssh -oBatchMode=yes -oStrictHostKeyChecking=no -oConnectTimeout=5 ${USER}@${HOST} "${COMMAND}" >> "$LOGDIR/$HOST" 2>&1 &
		hosts[$!]="$HOST";
		pidList="$pidList $!";
	done
}

function exec_remote_sudo_command() {
	get_pw

	for HOST in $HOSTS; do
		ssh -oBatchMode=yes -oStrictHostKeyChecking=no -oConnectTimeout=5 ${USER}@${HOST} "sudo -S -p '' bash -c '${COMMAND}'" <<<"$PW" >> "$LOGDIR/$HOST" 2>&1 &
		hosts[$!]="$HOST";
		pidList="$pidList $!";
	done
}

function exec_remote_command_with_sshpass() {
	get_pw

	for HOST in $HOSTS; do
		sshpass ssh -oStrictHostKeyChecking=no -oConnectTimeout=5 ${USER}@${HOST} "${COMMAND}" <<<"$PW" >> "$LOGDIR/$HOST" 2>&1 &
		hosts[$!]="$HOST";
		pidList="$pidList $!";
	done
}


if [ "$COPYID" == "TRUE" ]; then
	ssh_copy_id
else
	if [ "$ENABLE_SUDO" == "TRUE" ]; then
		exec_remote_sudo_command
	else
		if [ "$ENABLE_SSHPASS" == "TRUE" ]; then
			exec_remote_command_with_sshpass
		else
			exec_remote_command
		fi
	fi
fi


# Report status
for pid in $pidList; do
	HOST="${hosts[$pid]}"
	wait $pid
	RC=$?
	if [ "$RC" != "0" ]; then
		STATUS="FAILED"
		failedHosts="$failedHosts ${HOST}";
	else
		STATUS="PASSED"
	fi

	#echo "# $HOST | $STATUS | rc=$RC >>"
	echo -n "# $HOST | $STATUS | rc=$RC"

	if [ "$QUIET" != "TRUE" ]; then
		echo " >>";
		cat "$LOGDIR/$HOST";
		echo "";
	else
		echo "";
	fi

done

if [ "$failedHosts" != "" ]; then
	echo "# FAILED_HOSTS: $failedHosts";
	echo "$failedHosts" >> $FAILED_HOSTS;
fi
echo "# LOGDIR: $LOGDIR";
