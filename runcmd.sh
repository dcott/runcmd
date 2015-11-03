#!/bin/bash

# The runcmd.sh script is used to execute a shell command on large numbers
# systems via ssh. Commands can be run in series or in parallel. Output
# can be redirected to a separate log file for each host.
# 
# Public key authentication should be configured for your account on each
# host. The ssh command uses BatchMode and disables StrictHostKeyChecking
# to make things a bit more seemless. See ssh_config(5) for more details.
# 
# The -f options requires a file with a list of hostnames in the following
# format:
# 
# HOSTS="host1 host2 host3 ..."
# 
# The file is simply sourced and the HOSTS variable used.

# CONFIG VARS
LOGDIR="/var/tmp/runcmd"

# A Usage message to be printed on error or when user asks for help
USAGE='USAGE: runcmd.sh [hblq] -d delay -f filename -c "command string"\n'
USAGE=${USAGE}'\t-b instead of iterating over each host serially, fork and wait\n'
USAGE=${USAGE}'\t-h prints this message\n'
USAGE=${USAGE}'\t-l log results to a file\n'
USAGE=${USAGE}'\t-q do not print host status to stdout\n'
USAGE=${USAGE}'\t-f the filename that contains a list of hosts to operate on\n'
USAGE=${USAGE}'\t-c the command to run on each host (required)\n'
USAGE=${USAGE}'\t-d when running serially this adds a delay between hosts\n'

BACKGROUND=FALSE
CMD=FALSE
DELAY=FALSE
FILE=FALSE
LOG=FALSE
QUIET=FALSE
while getopts bc:d:f:hlq OPTION; do
	case $OPTION in
		(b)
			BACKGROUND=TRUE
			;;
		(c)
			CMD=TRUE
			COMMAND=$OPTARG
			;;
		(d)
			DELAY=TRUE
			DELAY_TIME=$OPTARG
			;;
		(f)
			FILE=TRUE
			HOST_FILE=$OPTARG
			;;
		(h)
			echo -en $USAGE
			exit 0
			;;
		(l)
			LOG=TRUE
			;;
		(q)
			QUIET=TRUE
			;;
	esac
done

if [ $LOG == TRUE ]; then
	TIMESTAMP=`date '+%Y_%m_%d_%H_%M_%S'`;
	LOGDIR="$LOGDIR/$TIMESTAMP";
	ERRORLOG="$LOGDIR/ERRORLOG";
	if ! mkdir -p $LOGDIR; then
		echo "### ERROR: Unable to create log dir '$LOGDIR'";
		exit 1;
	fi

	if ! echo "$COMMAND" > "$LOGDIR/COMMAND"; then
		echo "### ERROR: Unable to create COMMAND log file.";
		exit 1;
	fi
fi

# Make sure the user gave a command
if [ $CMD != TRUE ]; then
	echo -en $USAGE
	exit 0
fi

# Read in a list of hosts from a file
if [ $FILE == TRUE ]; then
	if [ -r $HOST_FILE ]; then
		source $HOST_FILE
	else
		echo "Could not source file: $HOST_FILE"
		exit 1;
	fi
else
	echo -en $USAGE
	exit 0
fi

if [ $BACKGROUND == FALSE ]; then
	for HOST in $HOSTS; do
		if [ $QUIET == FALSE ]; then
			echo "### $HOST"
		fi

		if ssh ${USER}@${HOST} "${COMMAND}"; then
			STATUS=pass
		else
			STATUS=fail
			failedHosts="$failedHosts $HOST"
		fi

		if [ $QUIET == FALSE ]; then
			echo "### $STATUS"
			echo ""
		fi

		if [ $LOG == TRUE ]; then
			TIMESTAMP=`date "+%b %d %Y %H:%M:%S"`
			echo "$TIMESTAMP $HOST $STATUS" >> $ERRORLOG
		fi

		if [ $DELAY == TRUE ]; then
			sleep $DELAY_TIME;
		fi
	done
else
	for HOST in $HOSTS; do
		if [ $QUIET == FALSE ]; then
			echo "Sending command to: $HOST";
		fi
		if [ $LOG == TRUE ]; then
			ssh -oBatchMode=yes -oStrictHostKeyChecking=no ${USER}@${HOST} "${COMMAND}" >> "$LOGDIR/$HOST" 2>&1 &
		else
			ssh -oBatchMode=yes -oStrictHostKeyChecking=no ${USER}@${HOST} "${COMMAND}" >> /dev/null 2>&1 &
		fi
		pids[$!]="$HOST";
		pidList="$pidList $!";
	done

	for pid in $pidList; do
		if ! wait $pid; then
			failedHosts="$failedHosts ${pids[$pid]}";
		fi
	done
fi

if [ "$failedHosts" != "" ]; then
	echo "FAILED HOSTS: $failedHosts";
	if [ $LOG == TRUE ]; then
		echo "FAILED HOSTS: $failedHosts" >> $ERRORLOG;
	fi
fi
