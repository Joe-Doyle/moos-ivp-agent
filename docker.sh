#!/usr/bin/env bash

# Cd to dir to make paths uniform
DIRNAME="$(dirname $0)"
cd $DIRNAME

# Make sure script exits if sub commands fail
set -e

# Test OS type for use letter
OS_TYPE="UNSET"

if [ "$(uname)" == "Linux" ]; then
    OS_TYPE="linux"
elif [ "$(uname)" == "Darwin" ]; then
    OS_TYPE="osx"
else
    printf "ERROR: Unable to determine OS type.\n"
    exit 1
fi

# Define names or tags to use when testing / normal operation
NAME="mivp-agent"
if [[ -n "$2" ]]; then
    printf "Settting name to $2...\n"
    NAME="$2"
fi
TEST_NAME="$NAME-testing"

require_image(){
    if [[ "$(docker images -q $NAME)" == "" ]]; then
        printf "Error: Unable to find docker image with tag \"$NAME\".\n\n"
        printf "Maybe run ./docker.sh build to build it?\n"
        exit 1;
    fi
}

require_no_container(){
    if [[ "$(docker ps -a | grep $1)" != "" ]]; then
        printf "Error: Existing container with name \"$1\".\n"
        exit 1;
    fi
}

do_run(){
    if [[ "$1" == "" || "$2" == "" ]]; then
        printf "Error: do_run should be called with two arguments\n"
        exit 1
    fi
    if [[ "$OS_TYPE" == "osx" ]]; then
        docker run --env="DISPLAY=host.docker.internal:0" \
            --volume="/tmp/.X11-unix:/tmp/.X11-unix" \
            --mount type=bind,source="$(pwd)"/missions,target=/home/moos/moos-ivp-agent/missions \
            --mount type=bind,source="$(pwd)"/src,target=/home/moos/moos-ivp-agent/src \
            --mount type=bind,source="$(pwd)"/examples,target=/home/moos/moos-ivp-agent/examples \
            --workdir="/home/moos/moos-ivp-agent" \
            --name "$2" "-it$3" "$1:1.0" bash
    elif [[ "$OS_TYPE" == "linux" ]]; then
        docker run --env="DISPLAY" \
            --volume="/tmp/.X11-unix:/tmp/.X11-unix" \
            --mount type=bind,source="$(pwd)"/missions,target=/home/moos/moos-ivp-agent/missions \
            --mount type=bind,source="$(pwd)"/src,target=/home/moos/moos-ivp-agent/src \
            --mount type=bind,source="$(pwd)"/examples,target=/home/moos/moos-ivp-agent/examples \
            --workdir="/home/moos/moos-ivp-agent" \
	    --user "$(id -u):$(id -g)" \
            --name "$2" "-it$3" "$1:1.0" bash 
    fi
}

# Handle arguments
if [[ -z "$1" ]] || [[ "$1" = "help" ]] || [[ "$1" = "--help" ]] || [[ "$1" = "-h" ]]; then
    printf "Usage: %s <COMMAND>\n" $0
    printf "Commands:\n"
    printf "\t build   - Build docker container and tag as \"mivp-agent\"\n"
    printf "\t run     - Run a docker container from image tagged as \"mivp-agent\"\n"
    printf "\t stop    - Stops a docker container from image tagged as \"mivp-agent\"\n"
    printf "\t rm      - Removes a docker container from image tagged as \"mivp-agent\"\n"
    printf "\t connect - Connect to the docker containertagged ad \"mivp-agent\"\n"
    exit 0;
elif [[ "$1" == "build" ]]; then
    printf "Building mivp_agent container...\n"
    if [[ "$OS_TYPE" == "osx" ]]; then
        docker build -t "$NAME:1.0" \
            --build-arg USER_ID=1001 \
            --build-arg GROUP_ID=1001 .
    elif [[ "$OS_TYPE" == "linux" ]]; then
        docker build -t "$NAME:1.0" \
            --build-arg USER_ID=$(id -u) \
            --build-arg GROUP_ID=$(id -g) .
    fi
elif [[ "$1" == "run" ]]; then
    # Make sure an image has been build
    require_image
    require_no_container $NAME

    printf "Enabling xhost server...\n"
    xhost +
    printf "Starting docker container...\n"
    printf "\n==========================================\n"
    printf "= To exit and stop: run command \"exit\"   =\n"
    printf "= To detach: CTRL+p CTRL+q               =\n"
    printf "==========================================\n\n"

    do_run $NAME $NAME
    
    printf "WARNING: Docker container will run in background unless stopped\n"
elif [[ "$1" == "connect" ]]; then
    printf "Conecting to docker container...\n"
    printf "\n==========================================\n"
    printf "= To detach: CTRL+p CTRL+q               =\n"
    printf "==========================================\n\n"
    docker exec -it "$NAME" bash
elif [[ "$1" == "stop" ]]; then
    printf "Stopping docker container...\n"
    docker stop "$NAME"
elif [[ "$1" == "rm" ]]; then
    printf "Deleting docker container...\n"
    docker rm "$NAME"
elif [[ "$1" == "test" ]]; then
    require_image
    require_no_container $TEST_NAME

    printf "Starting container for testing...\n"
    do_run $NAME $TEST_NAME "d" > /dev/null
    printf "Running tests with docker container...\n"
    # Prevent failure for exiting script
    set +e

    test_clean_up(){
        # Reset -e
        set -e
 
        printf "Cleaning up test container...\n"
        docker stop "$TEST_NAME" > /dev/null
        docker rm "$TEST_NAME" > /dev/null
    }

    fail_test(){
        printf "====================================\n"
        printf " Failed \"$1\" tests\n"
        printf "====================================\n"
        test_clean_up
        exit 1
    }

    # Run environment tests
    printf "====================================\n"
    printf "             Environment            \n"
    printf "====================================\n"
    docker exec -it $TEST_NAME bash -c "./test/test_environment.sh" || fail_test "Environment"
    
    # Run C++ tests
    printf "====================================\n"
    printf "                C++                 \n"
    printf "====================================\n"
    docker exec -it $TEST_NAME bash -c "cd build && ctest --verbose; exit $?" || fail_test "C++"

    # Run python tests
    printf "====================================\n"
    printf "               Python               \n"
    printf "====================================\n"
    docker exec -it $TEST_NAME bash -c "cd src/python_module/test && ./test_all.py" || fail_test "Python"

    # Still need to clean up if no failures
    test_clean_up

    # Display results and exit
    EXIT="0"
elif [[ "$1" == "clean" ]]; then
    # Following run in sub shell so -e doesn't catch it
    NO_FAIL="$(docker stop $NAME)"
    NO_FAIL="$(docker rm $NAME)"
else
    printf "Error: Unrecognized argument\n"
    exit;
fi
