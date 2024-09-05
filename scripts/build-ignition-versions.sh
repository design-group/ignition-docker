#!/bin/bash

START_VERSION=${1:-22}
END_VERSION=${2:-42}
PUSH=${3:-false}
BASE_IMAGE=${4:-"ghcr.io/username/ignition-docker/ignition"}
BASE_VERSION="8.1"

build_command="docker buildx bake --file ./docker-bake.hcl"

if [ "$PUSH" = "true" ]; then
    build_command+=" --push"
else
    build_command+=" --load"
fi

for i in $(seq "$START_VERSION" "$END_VERSION"); do
    version="${BASE_VERSION}.${i}"
    build_command+=" --set default.args.IGNITION_VERSION=$version --set default.tags=$BASE_IMAGE:$version"
done

build_command+=" default"

echo "Executing: $build_command"
eval "$build_command"