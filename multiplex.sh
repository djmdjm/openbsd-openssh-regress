#	$OpenBSD: multiplex.sh,v 1.15 2012/09/10 00:49:21 dtucker Exp $
#	Placed in the Public Domain.

CTL=$OBJ/ctl-sock

tid="connection multiplexing"

DATA=/bin/ls
COPY=$OBJ/ls.copy

start_sshd

trace "start master, fork to background"
${SSH} -Nn2 -MS$CTL -F $OBJ/ssh_config -oSendEnv="_XXX_TEST" somehost &
MASTER_PID=$!

# Wait for master to start and authenticate
sleep 5

verbose "test $tid: envpass"
trace "env passing over multiplexed connection"
_XXX_TEST=blah ${SSH} -F $OBJ/ssh_config -oSendEnv="_XXX_TEST" -S$CTL otherhost sh << 'EOF'
	test X"$_XXX_TEST" = X"blah"
EOF
if [ $? -ne 0 ]; then
	fail "environment not found"
fi

verbose "test $tid: transfer"
rm -f ${COPY}
trace "ssh transfer over multiplexed connection and check result"
${SSH} -F $OBJ/ssh_config -S$CTL otherhost cat ${DATA} > ${COPY}
test -f ${COPY}			|| fail "ssh -Sctl: failed copy ${DATA}" 
cmp ${DATA} ${COPY}		|| fail "ssh -Sctl: corrupted copy of ${DATA}"

rm -f ${COPY}
trace "ssh transfer over multiplexed connection and check result"
${SSH} -F $OBJ/ssh_config -S $CTL otherhost cat ${DATA} > ${COPY}
test -f ${COPY}			|| fail "ssh -S ctl: failed copy ${DATA}" 
cmp ${DATA} ${COPY}		|| fail "ssh -S ctl: corrupted copy of ${DATA}"

rm -f ${COPY}
trace "sftp transfer over multiplexed connection and check result"
echo "get ${DATA} ${COPY}" | \
	${SFTP} -S ${SSH} -F $OBJ/ssh_config -oControlPath=$CTL otherhost >>$TEST_SSH_LOGFILE 2>&1
test -f ${COPY}			|| fail "sftp: failed copy ${DATA}" 
cmp ${DATA} ${COPY}		|| fail "sftp: corrupted copy of ${DATA}"

rm -f ${COPY}
trace "scp transfer over multiplexed connection and check result"
${SCP} -S ${SSH} -F $OBJ/ssh_config -oControlPath=$CTL otherhost:${DATA} ${COPY} >>$TEST_SSH_LOGFILE 2>&1
test -f ${COPY}			|| fail "scp: failed copy ${DATA}" 
cmp ${DATA} ${COPY}		|| fail "scp: corrupted copy of ${DATA}"

rm -f ${COPY}

for s in 0 1 4 5 44; do
	trace "exit status $s over multiplexed connection"
	verbose "test $tid: status $s"
	${SSH} -F $OBJ/ssh_config -S $CTL otherhost exit $s
	r=$?
	if [ $r -ne $s ]; then
		fail "exit code mismatch for protocol $p: $r != $s"
	fi

	# same with early close of stdout/err
	trace "exit status $s with early close over multiplexed connection"
	${SSH} -F $OBJ/ssh_config -S $CTL -n otherhost \
                exec sh -c \'"sleep 2; exec > /dev/null 2>&1; sleep 3; exit $s"\'
	r=$?
	if [ $r -ne $s ]; then
		fail "exit code (with sleep) mismatch for protocol $p: $r != $s"
	fi
done

verbose "test $tid: cmd check"
${SSH} -F $OBJ/ssh_config -S $CTL -Ocheck otherhost >>$TEST_SSH_LOGFILE 2>&1 \
    || fail "check command failed" 

verbose "test $tid: cmd exit"
${SSH} -F $OBJ/ssh_config -S $CTL -Oexit otherhost >>$TEST_SSH_LOGFILE 2>&1 \
    || fail "send exit command failed" 

# Wait for master to exit
sleep 2

ps -p $MASTER_PID >/dev/null && fail "exit command failed"

# Restart master and test -O stop command with master using -N
trace "start master, fork to background"
${SSH} -Nn2 -MS$CTL -F $OBJ/ssh_config -oSendEnv="_XXX_TEST" somehost &
MASTER_PID=$!
sleep 5 # Wait for master to start and authenticate
verbose "test $tid: cmd stop"
${SSH} -F $OBJ/ssh_config -S $CTL otherhost "sleep 10; exit 0" &
SLEEP_PID=$!
${SSH} -F $OBJ/ssh_config -S $CTL -Ostop otherhost >>$TEST_SSH_LOGFILE 2>&1 \
    || fail "send stop command failed"
sleep 12 # Wait for master to exit
wait $SLEEP_PID
[ $! != 0 ] || fail "stop with concurrent command"
ps -p $MASTER_PID >/dev/null && fail "stop command failed"
