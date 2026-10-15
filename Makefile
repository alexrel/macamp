# MacAmp Makefile
.PHONY: all build run release run-release clean dmg help

all: build

build:
	@./build.sh build

run:
	@./build.sh run

release:
	@./build.sh release

run-release:
	@./build.sh run-release

clean:
	@./build.sh clean

dmg:
	@./build.sh dmg

help:
	@./build.sh help
