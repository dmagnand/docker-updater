#!/bin/bash
##############################################
####  Updating docker containers on the server  ####
##############################################

####  python and jq must be installed ######
apt-get -y install jq python
if [ $? != 0 ]; then
	logger -s " python jq must be installed ! script aborted.";
	exit 1;
fi;
######################################

TIMESTAMP=`date "+%Y.%d.%m"`

# Syslog message for start of container updates
logger -t backup "Beginning container updates for $TIMESTAMP"

DOCKER_STOP="docker stop"
DOCKER_RM="docker rm"
DOCKER_PULL="docker pull"
DOCKER_RUN="docker run"

CONTAINERS=`docker ps --format "{{.Names}}" | sort`

for container in $CONTAINERS
do :
	CMD=`$DOCKER_STOP $container`
	# Fail Check
	if [ $? != 0 ]; then
		logger -s "DOCKER STOP ERROR: Problem prevented $container stopping. Stop command aborted.";
		logger -s $CMD;
		exit 1;
	fi;
	logger -s "Docker stopped $container successfully";
	JSON=`docker container inspect $container`
	BINDS=`echo $JSON | jq -j '.[] | .HostConfig | .Binds[] as $b | "-v \($b) "'`
	PORTS=`echo $JSON | jq ' .[] | .HostConfig | .PortBindings | keys[] as $k | "\($k):\(.[$k][] | .HostPort )" ' | while read -r line; do python -c $"print('-p ' + $line.replace('/tcp',).split(':')[1] + ':' + $line.replace('/tcp',).split(':')[0])"; done | awk '{print}' ORS=' '`
	IMAGE=`echo $JSON | jq -r '.[] | .Config | .Image'`
	ENV=`echo $JSON | jq -j '.[] | .Config | .Env[] as $e | "-e \($e) "'`

	CMD=`$DOCKER_RM $container`
	# Fail Check
	if [ $? != 0 ]; then
		logger -s "DOCKER REMOVE ERROR: Problem prevented $container from being removed. Remove command aborted.";
		logger -s $CMD;
		exit 1;
	fi;
	logger -s "Docker removed $container successfully";

	CMD=`$DOCKER_PULL $IMAGE`
	# Fail Check
	if [ $? != 0 ]; then
		logger -s "DOCKER PULL ERROR: Problem prevented $container from being pulled from website. Pull command aborted.";
		logger -s $CMD;
		exit 1;
	fi;
	logger -s "Docker pulled new container successfully";

	CMD=`$DOCKER_RUN --restart always -d --name=$container $PORTS $BINDS $ENV $IMAGE`
	# Fail Check
	if [ $? != 0 ]; then
		logger -s "DOCKER RESTART ERROR: Problem prevented $container from being restarted. Restart command aborted.";
		logger -s $CMD;
		exit 1;
	fi;
	logger -s "Docker restarted $container successfully";
done

# Check all containers are restarted
NEWCONTAINERS=`docker ps --format "{{.Names}}" | sort`
if [ $NEWCONTAINERS != $CONTAINERS ]; then
	logger -s "WARNING: All containers are NOT restarted. List of running container before update:$CONTAINERS - List of running container after: $NEWCONTAINERS";
	exit 1;
fi;

CMD=`docker system prune -a -f`
# Fail Check
if [ $? != 0 ]; then
	logger -s "DOCKER PRUNE ERROR: Problem prevented clean up of unused containers. Prune command aborted.";
	logger -s $CMD;
	exit 1;
fi;
logger -s "All unused information has been removed successfully";


# Syslog message for end of container updates
logger -t backup "Completed container updates for $TIMESTAMP"

#############################################################
