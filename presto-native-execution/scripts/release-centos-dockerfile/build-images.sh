#!/usr/bin/env bash

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
source $SCRIPT_DIR/release-dockerfile/opt/common.sh

set -eE -o pipefail
trap 'error "Stage failed, exiting"; exit 5' SIGSTOP SIGINT SIGTERM SIGQUIT ERR

print_logo

export CPU_TARGET=${CPU_TARGET:-'avx'}
export BASE_IMAGE=${BASE_IMAGE:-'quay.io/centos/centos:stream8'}
export IMAGE_NAME=${IMAGE_NAME:-"presto/prestissimo-${CPU_TARGET}-centos"}
export IMAGE_TAG=${IMAGE_TAG:-"latest"}
export IMAGE_REGISTRY=${IMAGE_REGISTRY:-''}
export IMAGE_PUSH=${IMAGE_PUSH:-'0'}

export STAGE1_USER_FLAGS=${STAGE1_USER_FLAGS:-''}
export STAGE2_USER_FLAGS=${STAGE2_USER_FLAGS:-''}
export GLOBAL_USER_FLAGS=${GLOBAL_USER_FLAGS:-''}

export PRESTOCPP_ROOT_DIR=${PRESTOCPP_ROOT_DIR:-"$(readlink -f "$SCRIPT_DIR/../..")"}
export PRESTODB_REPOSITORY=${PRESTODB_REPOSITORY:-"$(cd "${PRESTOCPP_ROOT_DIR}/.." && git config --get remote.origin.url)"}
export PRESTODB_CHECKOUT=${PRESTODB_CHECKOUT:-"$(cd "${PRESTOCPP_ROOT_DIR}/.." && git show -s --format="%H" HEAD)"}

(
    prompt "Using build time variables:"
    prompt "\tIMAGE_NAME=${IMAGE_NAME}"
    prompt "\tIMAGE_TAG=${IMAGE_TAG}"
    prompt "\tIMAGE_REGISTRY=${IMAGE_REGISTRY}"
    prompt "\tBASE_IMAGE=${BASE_IMAGE}"
    prompt "\tCPU_TARGET=${CPU_TARGET}"
    prompt "\tSTAGE1_USER_FLAGS=${STAGE1_USER_FLAGS}"
    prompt "\tSTAGE2_USER_FLAGS=${STAGE2_USER_FLAGS}"
    prompt "\tGLOBAL_USER_FLAGS=${GLOBAL_USER_FLAGS}"
    prompt "---"
    prompt "\tPRESTODB_REPOSITORY=${PRESTODB_REPOSITORY}"
    prompt "\tPRESTODB_CHECKOUT=${PRESTODB_CHECKOUT}"
    prompt "---"
    prompt "Using build time computed variables:"
    prompt "\t[1/2] Base build image: ${BASE_IMAGE}"
    prompt "\t[1/2] Base build image tag: ${IMAGE_REGISTRY}${IMAGE_NAME}-base:${IMAGE_TAG}"
    prompt "\t[2/2] Release image tag: ${IMAGE_REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"
    prompt "---"
) 2>&1
(
    prompt "[1/2] Preflight Git checks stage starting $(txt_yellow remote commit exisitance)" &&
    prompt "[1/2] Fetching remote repository" &&
    cd "${PRESTOCPP_ROOT_DIR}/.." > /dev/null &&
    git fetch --all > /dev/null &&
    prompt "[1/2] Checking if local hash is available on remote repository" &&
    git branch -r --contains $PRESTODB_CHECKOUT > /dev/null ||
    ( error '[1/2] Preflight stage failed, commit not found. Exiting.' && exit 1 )
) 2>&1
(
    prompt "[2/2] Preflight CPU checks stage starting $(txt_yellow processor instructions)"
    error=0
    check=$(txt_green success)
    prompt "Velox build requires bellow CPU instructions to be available:"
    for flag in 'bmi|bmi1' 'bmi2' 'f16c';
    do
        echo $(cat /proc/cpuinfo) | grep -E -q " $flag " && check=$(txt_green success) || check=$(txt_red failed) error=1
        prompt "Testing (${flag}): \t$check"
    done
    prompt "Velox build suggest bellow CPU instructions to be available:"
    for flag in avx avx2 sse;
    do
        echo $(cat /proc/cpuinfo) | grep -q " $flag " && check=$(txt_green success) || check=$(txt_yellow failed)
        prompt "Testing (${flag}): \t$check"
    done
    [ $error -eq 0 ] || ( error 'Preflight checks failed, lack of CPU functionality. Exiting.' && exit 1 )
    prompt "[2/2] Preflight CPU checks $(txt_green success)"
) |
tee "$SCRIPT_DIR/preflight_1_of_1.log"
(
    prompt "[1/2] Build stage starting $(txt_yellow ${IMAGE_REGISTRY}${IMAGE_NAME}-base:${IMAGE_TAG})" &&
    cd "${SCRIPT_DIR}" &&
    docker build $GLOBAL_USER_FLAGS $STAGE1_USER_FLAGS \
        --network=host \
        --build-arg http_proxy  \
        --build-arg https_proxy \
        --build-arg no_proxy    \
        --build-arg CPU_TARGET  \
        --build-arg BASE_IMAGE \
        --build-arg PRESTODB_REPOSITORY \
        --build-arg PRESTODB_CHECKOUT \
        --tag "${IMAGE_REGISTRY}${IMAGE_NAME}-base:${IMAGE_TAG}" \
        ./dependencies-dockerfile &&
    prompt "[1/2] Build finished" &&
    (
        [ "$IMAGE_PUSH" == "1" ] &&
        prompt "[1/2] Pushing image $(txt_yellow ${IMAGE_REGISTRY}${IMAGE_NAME}-base:${IMAGE_TAG})" &&
        docker push "${IMAGE_REGISTRY}${IMAGE_NAME}-base:${IMAGE_TAG}" || true
    ) &&
    prompt "[1/2] Build stage for base image finished $(txt_green ${IMAGE_REGISTRY}${IMAGE_NAME}-base:${IMAGE_TAG})" ||
    ( error '[1/2] Build stage failed. Exiting' && exit 2 )
) |
tee "$SCRIPT_DIR/stage_1_of_2.log"
(
    prompt "[2/2] Build stage starting" &&
    cd "${SCRIPT_DIR}" &&
    docker build $GLOBAL_USER_FLAGS $STAGE2_USER_FLAGS \
        --network=host \
        --build-arg http_proxy  \
        --build-arg https_proxy \
        --build-arg no_proxy    \
        --build-arg IMAGE_NAME  \
        --build-arg IMAGE_TAG   \
        --build-arg IMAGE_REGISTRY \
        --build-arg PRESTODB_REPOSITORY \
        --build-arg PRESTODB_CHECKOUT \
        --pull=false \
        --tag "${IMAGE_REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}" \
        ./release-dockerfile &&
    prompt "[2/2] Build finished" &&
    (
        [ "$IMAGE_PUSH" == "1" ] &&
        prompt "[2/2] Pushing image $(txt_yellow ${IMAGE_REGISTRY}${IMAGE_NAME}:${IMAGE_TAG})" &&
        docker push "${IMAGE_REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}" || true
    ) &&
    prompt "[2/2] Build stage finished $(txt_green success)" ||
    ( error '[2/2] Build stage failed. Exiting' && exit 4 )
) |
tee "$SCRIPT_DIR/stage_2_of_2.log"
prompt "Prestissimo is ready for deployment"
prompt "Image tagged as: ${IMAGE_REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"

