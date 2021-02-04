#!/bin/bash
# Start the Vigor container
set -euxo pipefail

IMAGE_NAME='dslabepfl/vigor'


if ! PARAMS=$(getopt -o n: -l vfio:,name: -n "$0" -- "$@"); then
    exit 1
fi

eval set -- "$PARAMS"

DOCKER_PARAMS="-i -t --privileged --device=/dev/hugepages:/dev/hugepages"
while true; do
    case "$1" in
        --vfio )
            DOCKER_PARAMS="$DOCKER_PARAMS --device=/dev/vfio/$2:/dev/vfio/$2"
            shift 2
            ;;
        -n | --name )
            DOCKER_PARAMS="$DOCKER_PARAMS --name=$2"
            shift 2
            ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

sudo docker run $DOCKER_PARAMS "$IMAGE_NAME"
