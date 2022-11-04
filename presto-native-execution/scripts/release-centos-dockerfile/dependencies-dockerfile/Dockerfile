# prestissimo/base

# /////////////////////////////////
#    BUILD TASK START
# /////////////////////////////////
#============================================================
#---( START of prestissimo base image container definition

# ARG IMAGE_CACHE_REGISTRY=ger-is-registry.caas.intel.com/cache/
ARG BASE_IMAGE=quay.io/centos/centos:stream8
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="Prestissimo Base Image" \
      org.opencontainers.image.description="Prestissimo Base Docker image for use as starting point for Velox and PresoCpp builds" \
      org.opencontainers.image.version="1.0.0"

ARG CPU_TARGET=avx
ARG CMAKE_PREFIX_PATH=/usr/local
ARG DEPENDENCY_DIR=/opt/dependency
ARG GIT_PRESTO_NATIVE_DIR=${DEPENDENCY_DIR}/presotdb-git/presto-native-execution
ARG GIT_VELOX_DIR=${GIT_PRESTO_NATIVE_DIR}/velox
ARG ADAPTER_DEPENDENCY_DIR=${DEPENDENCY_DIR}/adapter-deps

ARG PRESTODB_REPOSITORY=https://github.com/prestodb/presto
ARG PRESTODB_CHECKOUT=origin/master

ENV CPU_TARGET=${CPU_TARGET}
ENV CMAKE_PREFIX_PATH=/usr/local
ENV TZ=Europe/Warsaw
ENV CC=/opt/rh/gcc-toolset-9/root/bin/gcc
ENV CXX=/opt/rh/gcc-toolset-9/root/bin/g++

USER root:root

#---( START Docker proxy settings

ARG http_proxy=""
ARG https_proxy=""
ARG no_proxy=""

ENV http_proxy=${http_proxy}
ENV HTTP_PROXY=${http_proxy}
ENV https_proxy=${https_proxy}
ENV HTTPS_PROXY=${https_proxy}
ENV no_proxy=${no_proxy}
ENV NO_PROXY=${no_proxy}

#---) END Docker proxy settings
#-----------------------------------------------------------
#---( Dependencies install for both velox and prestocpp
RUN set -exu && \
        dnf -y install bash bzip2 bzip2-libs uuid hostname vim git jq unzip pkg-config python3 python3-devel maven java clang-tools-extra perl-XML-XPath && \
        dnf clean all
#---( START PrestoDB and Velox dependency tree build scripts
SHELL ["/bin/bash", "-c"]
WORKDIR "${DEPENDENCY_DIR}"
RUN set -exu && \
        git clone ${PRESTODB_REPOSITORY} presotdb-git && \
        ( \
          cd presotdb-git && \
          git checkout ${PRESTODB_CHECKOUT} && \
          git submodule update --init --recursive \
        ) && \
        mkdir -p "${DEPENDENCY_DIR}/build/scripts" "/usr/local/.client" && \
        cp "${GIT_PRESTO_NATIVE_DIR}/scripts/setup-centos.sh" "${DEPENDENCY_DIR}/build/scripts/setup-centos.sh" && \
        cp "${GIT_VELOX_DIR}/scripts/setup-circleci.sh" "${DEPENDENCY_DIR}/build/scripts/setup-circleci.sh" && \
        cp "${GIT_VELOX_DIR}/scripts/setup-helper-functions.sh" "${DEPENDENCY_DIR}/build/scripts/setup-helper-functions.sh" && \
        ( \
          cd "${DEPENDENCY_DIR}/build/scripts" && \
          bash "setup-circleci.sh" && \
          bash "setup-centos.sh" \
        ) && \
#---( END of Velox dependency tree build scripts
#-----------------------------------------------------------
#---( START wget valid antlr java runtime and wrap it as only libraries are installed in previous steps \
        wget -q 'https://www.antlr.org/download/antlr-4.9.3-complete.jar' -O '/usr/local/lib/antlr-4.9.3-complete.jar' && \
        printf '#!/usr/bin/bash\n\njava -jar /usr/local/lib/antlr-4.9.3-complete.jar "$@"' > '/usr/local/bin/antlr' && \
        chmod +x "/usr/local/bin/antlr" && \
#---) END of wget valid antlr
#-----------------------------------------------------------
#---( START of third party dependency preparation
        wget -q "https://dl.min.io/server/minio/release/linux-amd64/archive/minio-20220526054841.0.0.x86_64.rpm" && \
        rpm -i "minio-20220526054841.0.0.x86_64.rpm" && \
#---) END of third party dependency preparation
#-----------------------------------------------------------
#---( START of cleanup process
        rm -rf "minio-20220526054841.0.0.x86_64.rpm" "${DEPENDENCY_DIR}/build/scripts" "${DEPENDENCY_DIR}/presotdb-git" /tmp/* && \
        dnf clean all
#---) END of third party dependency preparation
#-----------------------------------------------------------
#---( START export environment variables with paths needed in next stages

COPY etc/hdfs-client.xml "/usr/local/.client/hdfs-client.xml"

ENV DEPENDENCY_DIR=/opt/dependency
ENV ADAPTER_DEPENDENCY_DIR=${DEPENDENCY_DIR}/adapter-deps

ENV HADOOP_ROOT_LOGGER="WARN,DRFA"
ENV LIBHDFS3_CONF=${ADAPTER_DEPENDENCY_DIR}/install/bin/.client/hdfs-client.xml
ENV PATH=${ADAPTER_DEPENDENCY_DIR}/install/bin:${ADAPTER_DEPENDENCY_DIR}/install/bin/hadoop-2.10.1/bin:$PATH

#---) END  export environment variables with paths needed in next stages
#============================================================
# /////////////////////////////////
#    BUILD TASK END
# /////////////////////////////////
