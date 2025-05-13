#!/bin/bash
####################################################
####  Updating docker containers on the server  ####
####  Fork from https://github.com/godofjesters/docker-updater/
####  Modified by dmagnand for my own use
####  https://github.com/dmagnand/docker-updater/
####  This script is used to update all docker containers on the server.	
####  It will stop all containers, remove them, pull the latest images,
####  restart the containers and then remove the unused containers.
####  It will also log the output to the syslog.
####  Version 1.0
####  Date 2025-05-12
####  Warning: container must be named --name (for checking if all containers are restarted)
####  update to python3
####  Add check if container still exists before trying to remove it (in case of use of --rm option) it cause DOCKER REMOVE ERROR
####  Add change from godofjesters script Commit c67f7e8
####  unify the logger output	
####################################################

# Check if python3 and jq are installed
if ! command -v python3 &> /dev/null; then
    logger -t DockerUpdater -s "python3 is not installed"
    PYTHON_MISSING=1
fi

if ! command -v jq &> /dev/null; then
    logger -t DockerUpdater -s "jq is not installed" 
    JQ_MISSING=1
fi

if [[ -n "${PYTHON_MISSING}" || -n "${JQ_MISSING}" ]]; then
    logger -t DockerUpdater -s "python3 and jq must be installed ! script aborted.";
	exit 1;
fi
#####################################################

TIMESTAMP=$(date "+%Y.%d.%m")

# Syslog message for start of container updates
logger -t DockerUpdater -s "Beginning container updates for ${TIMESTAMP}"

DOCKER_STOP="docker stop"
DOCKER_RM="docker rm"
DOCKER_PULL="docker pull"
DOCKER_RUN="docker run"

#uncomment the line with $1 to be able to run the updater with a single container: "./docker_updater.sh containername"
#CONTAINERS=`docker ps --format "$1"`

CONTAINERS=`docker ps --format "{{.Names}}" | sort`

for container in ${CONTAINERS}
do :
	# Container inspect before stopping it
	logger -t DockerUpdater-s "Docker stopped ${container} successfully";
	JSON=`docker container inspect ${container}`
	echo ${JSON} > ${container} + ".json"
	if [ -z "$(echo ${JSON} | jq -j '.[] | .HostConfig | .Binds')" ]; then
			BINDS=""
		else
			BINDS=$(echo ${JSON} | jq -j '.[] | .HostConfig | .Binds[] as $b | "-v \($b) "')
	fi;
	if [ -z "$(echo ${JSON} | jq -j '.[] | .HostConfig | .ExtraHosts')" ]; then
			EXTRAHOSTS=""
		else
			EXTRAHOSTS=$(echo ${JSON} | jq -j '.[] | .HostConfig | .ExtraHosts[] as $h | "--add-host=\($h) "')
	fi;
	if [ -z "$(echo ${JSON} | jq ' .[] | .HostConfig | .PortBindings | keys ')" ]; then
			PORTS=""
		else
			PORTS=$(echo ${JSON} | jq ' .[] | .HostConfig | .PortBindings | keys[] as $k | "\($k):\(.[$k][] | .HostPort )" ' | while read -r line; do python3 -c $"print('-p ' + $line.replace('/tcp','').split(':')[1] + ':' + $line.replace('/tcp','').split(':')[0])"; done | awk '{print}' ORS=' ')
	fi;
	IMAGE=$(echo ${JSON} | jq -r '.[] | .Config | .Image')
	#ENV=`echo ${JSON} | jq -j '.[] | .Config | .Env[] as $e | "-e \($e) "'`
	ENV=$(echo ${JSON} | jq -j '.[] | .Config | .Env[] | split("=") | " --env \(.[0])=\(.[1]|@sh)"')

	# Stop container
	CMD=`${DOCKER_STOP} ${container}`
	# Fail Check
	if [ $? != 0 ]; then
		logger -t DockerUpdater -s "DOCKER STOP ERROR: Problem prevented ${container} stopping. Stop command aborted.";
		logger -s ${CMD};
		exit 1;
	fi;
	logger -t DockerUpdater -s "Container ${container} stopped successfully";

	# Check if container still exists before trying to remove it (use of --rm option)
	if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
		logger -t DockerUpdater -s "Container ${container} exists, proceeding with removal"
		CMD=`${DOCKER_RM} ${container}`
		# Fail Check
		if [ $? != 0 ]; then
			logger -t DockerUpdater -s "DOCKER REMOVE ERROR: Problem prevented ${container} from being removed. Remove command aborted.";
			exit 1;
		fi;
		logger -t DockerUpdater -s "Docker removed ${container} successfully";
	else
		logger -t DockerUpdater -s "Container ${container} already removed, skipping removal step"
		continue
	fi;

	CMD=`${DOCKER_PULL} ${IMAGE}`
	# Fail Check
	if [ $? != 0 ]; then
		logger -t DockerUpdater -s "DOCKER PULL ERROR: Problem prevented ${container} from being pulled from website. Pull command aborted.";
		exit 1;
	fi;
	logger -s "Docker pulled new container successfully";

	CMD=`${DOCKER_RUN} ${EXTRAHOSTS} --restart always -d --name=${container} ${PORTS} ${BINDS} ${ENV} ${IMAGE}`
	# Fail Check
	if [ $? != 0 ]; then
		logger -t DockerUpdater -s "DOCKER RESTART ERROR: Problem prevented ${container} from being restarted. Restart command aborted.";
		logger -t DockerUpdater -s ${CMD};
		exit 1;
	fi;
	logger -t DockerUpdater -s "Docker restarted ${container} successfully";
done

# Check all containers are restarted before prune
NEWCONTAINERS=`docker ps --format "{{.Names}}" | sort`
if [ ${NEWCONTAINERS} != ${CONTAINERS} ]; then
	logger -t DockerUpdater -s "WARNING: All containers are NOT restarted. List of running container before update:${CONTAINERS} - List of running container after: ${NEWCONTAINERS}";
	exit 1;
fi;

CMD=`docker system prune -a -f`
# Fail Check
if [ $? != 0 ]; then
	logger -t DockerUpdater -s "DOCKER PRUNE ERROR: Problem prevented clean up of unused containers. Prune command aborted.";
	logger -t DockerUpdater -s ${CMD};
	exit 1;
fi;
logger -t DockerUpdater -s "All unused information has been removed successfully";


# Syslog message for end of container updates
logger -t DockerUpdater -s "Completed container updates for ${TIMESTAMP}"

#############################################################
