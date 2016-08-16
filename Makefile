GOOS:=linux
VERSION:=$(shell git describe --abbrev=4 --always --tags)
NAME:=mesos-dns
CONTAINERNAME:=$(NAME)
CIRCLE_TEST_REPORTS?=$(PWD)
CIRCLE_ARTIFACTS?=$(PWD)/build
COVERALLS_REPO_TOKEN?="tokennotset"
DOCKER?=

all: $(if $(DOCKER), dockerbuild) test build

deps:
	go get -u github.com/kardianos/govendor
	go get -u github.com/mitchellh/gox
	go get -u github.com/alecthomas/gometalinter
	go get -u github.com/axw/gocov/gocov
	go get -u github.com/mattn/goveralls
	go get -u github.com/jstemmer/go-junit-report
	gometalinter --install
	govendor sync
	go install ./...
	go test -i ./...

dockerbuild:
	docker build -t $(CONTAINERNAME)-build -f Dockerfile.test .

test: fmttest metalinter gocov junit gorace

## Ignore vendored dependencies
## Return 1 if any files found that haven't been formatted
fmttest: $(if $(DOCKER), dockerbuild)
	$(if $(DOCKER), docker run --rm $(CONTAINERNAME)-build) gofmt -l . | \
								awk '!/^vendor/ { print $0; err=1 }; END{ exit err }'

junit: $(if $(DOCKER), dockerbuild)
	mkdir -p $(CIRCLE_TEST_REPORTS)/junit
	@# This seems odd, but if you attach stdin without attaching to an
	@# output ( stdout or stderr ), the container runs in the background
	$(if $(DOCKER), docker run --rm $(CONTAINERNAME)-build) go test -v -timeout=10m ./... | \
	$(if $(DOCKER), docker run --rm -i -a stdin -a stdout -a stderr $(CONTAINERNAME)-build ) go-junit-report > $(CIRCLE_TEST_REPORTS)/junit/alltests.xml

metalinter: $(if $(DOCKER), dockerbuild)
	$(if $(DOCKER), docker run --rm $(CONTAINERNAME)-build) gometalinter \
							--vendor \
							--concurrency=6 \
							--cyclo-over=12 \
							--tests \
							--exclude='TLS InsecureSkipVerify may be true.' \
							--exclude='Use of unsafe calls should be audited' \
							--deadline=300s ./...

gocov: $(if $(DOCKER), dockerbuild)
	$(if $(DOCKER), docker run --rm $(CONTAINERNAME)-build) gocov test ./... -short -timeout=10m > $(PWD)/cov.json

gorace: $(if $(DOCKER), dockerbuild)
	$(if $(DOCKER), docker run --rm $(CONTAINERNAME)-build) go test -v -short -race -timeout=10m ./...

artifacts: $(if $(DOCKER), dockerbuild)
	$(if $(DOCKER), docker run --rm -v "$(CIRCLE_ARTIFACTS)":/output $(CONTAINERNAME)-build) gox -arch=amd64 -os="linux darwin windows" \
												-output="/output/{{.Dir}}-$(VERSION)-{{.OS}}-{{.Arch}}" \
												-ldflags="-X main.Version=$(VERSION)"

coveralls: $(if $(DOCKER), dockerbuild)
	$(if $(DOCKER), docker run --rm -v "$(PWD)":/coveralls $(CONTAINERNAME)-build) goveralls -service=circleci \
											-gocovdata=/coveralls/cov.json \
											-repotoken=$(COVERALLS_REPO_TOKEN) || true

build: $(if $(DOCKER), dockerbuild)
	$(if $(DOCKER), docker run --rm -v "$(PWD)/build":/build -e GOOS=$(GOOS) $(CONTAINERNAME)-build, env GOOS=$(GOOS)) go build -ldflags="-X main.Version=$(VERSION)" -o /build/mesos-dns

buildstatic: $(if $(DOCKER), dockerbuild)
	$(if $(DOCKER), docker run --rm -v "$(PWD)/build":/build -e CGO_ENABLED=0 -e GOOS=$(GOOS) $(CONTAINERNAME)-build, env CGO_ENABLED=0 GOOS=$(GOOS)) go build -a -installsuffix cgo \
																			-ldflags "-s -X main.Version=$(VERSION)" \
																			-o /build/mesos-dns

version:
	@echo "$(VERSION)"

clean:
	docker rmi $(CONTAINERNAME)-build || true
	docker rmi $(CONTAINERNAME) || true

help:
	@echo "all - run all tests and compile mesos-dns"
	@echo "artifacts - compiles the program using gox for linux darwin and windows platforms"
	@echo "build - compiles the program, env GOOS can be set to specifiy platform"
	@echo "buildstatic - compiles a statically linked program, env GOOS can be set to specify platform"
	@echo "clean - remove mesos-dns and mesos-dns-build docker images"
	@echo "coveralls - runs goveralls and uploads data to coveralls, env COVERALLS_REPO_TOKEN is needed"
	@echo "dockerbuild - create mesos-dns-build docker image"
	@echo "fmttest - runs gofmt, returns 0 for success, 1 for failure"
	@echo "gocov - runs gocov"
	@echo "gorace - runs go test with race detection enabled"
	@echo "junit - runs go test and generates junit output"
	@echo "metalinter - runs gometalinter"
	@echo "test - runs fmttest and the various tests against the source code"
	@echo "version - display current version"
