#!/bin/bash

START_VERSION=${1:-22}
END_VERSION=${2:-42}
PUSH=${3:-false}
BASE_VERSION="8.1"

build_command="docker buildx bake --file ./docker-bake.hcl"

if [ "$PUSH" = "true" ]; then
    build_command+=" --push"
else
    build_command+=" --load"
fi

for i in $(seq "$START_VERSION" "$END_VERSION"); do
    version="${BASE_VERSION}.${i}"
    build_command+=" --set ignition.args.IGNITION_VERSION=$version --set ignition.tags=ghcr.io/keith-gamble/ignition-docker:$version"
done

build_command+=" ignition"

echo "Executing: $build_command"

eval "$build_command"