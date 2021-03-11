all: build run

build:
	docker build -t reuploader .

build-no-cache:
	docker build --no-cache=true -t reuploader .

run:
	docker run -v reuploader:/mnt --rm -it reuploader

run-shell:
	docker run -v reuploader:/mnt --rm -it reuploader bash

