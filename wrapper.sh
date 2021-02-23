#!/usr/bin/env bash

#container="reuploader"
container="ondt/reuploader"

if [[ -f "$1" ]]; then
	sudo docker run --rm -it -v reuploader:/src/cookies -v "$1":/mnt/local_video "$container" /src/reuploader.sh "$1"
else
	sudo docker run --rm -it -v reuploader:/src/cookies "$container" /src/reuploader.sh "$1"
fi
