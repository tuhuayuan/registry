# Short name: Short name, following [a-zA-Z_], used all over the place.
# Some uses for short name:
# - Docker image name
# - Kubernetes service, rc, pod, secret, volume names
SHORT_NAME := registry

include includes.mk versioning.mk

# the filepath to this repository, relative to $GOPATH/src
REPO_PATH = github.com/deis/registry

# The following variables describe the containerized development environment
# and other build options
DEV_ENV_IMAGE := index.tenxcloud.com/tuhuayuan/go-dev:v1.0
DEV_ENV_WORK_DIR := /go/src/${REPO_PATH}
DEV_ENV_PREFIX := docker run --rm -e GO15VENDOREXPERIMENT=1 -v ${CURDIR}:${DEV_ENV_WORK_DIR} -w ${DEV_ENV_WORK_DIR}
DEV_ENV_CMD := ${DEV_ENV_PREFIX} ${DEV_ENV_IMAGE}
LDFLAGS := "-s -w -X main.version=${VERSION}"
BINDIR := ./rootfs/opt/registry/sbin

# Legacy support for DEV_REGISTRY, plus new support for DEIS_REGISTRY.
DEIS_REGISTRY ?= ${DEV_REGISTRY}

ifeq ($(STORAGE_TYPE),)
  STORAGE_TYPE = fs
endif

# Kubernetes-specific information for Secret, RC, Service, and Image.
RC := contrib/kubernetes/manifests/${SHORT_NAME}-rc.tmp.yaml
SVC := contrib/kubernetes/manifests/${SHORT_NAME}-service.yaml

all:
	@echo "Use a Makefile to control top-level building of the project."

build: check-docker
	mkdir -p ${BINDIR}
	$(MAKE) build-binary

# For cases where we're building from local
# We also alter the RC file to set the image name.
docker-build: check-docker build
	docker build --rm -t ${IMAGE} rootfs
	docker tag ${IMAGE} ${MUTABLE_IMAGE}

# Push to a registry that Kubernetes can access.
docker-push: check-docker
	docker push ${IMAGE}

build-binary:
	${DEV_ENV_CMD} go build -ldflags ${LDFLAGS} -o $(BINDIR)/${SHORT_NAME} main.go
	$(call check-static-binary,$(BINDIR)/${SHORT_NAME})
	${DEV_ENV_CMD} upx -9 --brute $(BINDIR)/${SHORT_NAME}

# Deploy is a Kubernetes-oriented target
deploy: kube-service kube-rc tls-secret

tls-secret: check-kubectl
	kubectl create secret generic registry-tls-cert \
		--from-file=tls.crt=${REGISTRY_TSL_CRT} \
		--from-file=tls.key=${REGISTRY_TSL_KEY} 

# Some things, like services, have to be deployed before pods. This is an
# example target. Others could perhaps include kube-volume, etc.
kube-service: check-kubectl
	kubectl create -f ${SVC}

# When possible, we deploy with RCs.
kube-rc: check-kubectl
	kubectl create -f ${RC}

kube-clean: check-kubectl
	kubectl delete -f ${SVC}
	kubectl delete -f ${RC}
	kubectl delete secret registry-tls-cert

test: check-docker
	contrib/ci/test.sh ${IMAGE}

update-manifests:
	sed 's#\(image:\) .*#\1 $(IMAGE)#' contrib/kubernetes/manifests/${SHORT_NAME}-rc.yaml \
		> ${RC}

.PHONY: all build kube-up kube-down deploy
