# prestissimo

# /////////////////////////////////
#    BUILD TASK DEFINITION
# /////////////////////////////////
#============================================================
ARG BASE_IMAGE=quay.io/centos/centos:stream8
FROM ${BASE_IMAGE} AS build-stage

ARG CPU_TARGET=avx
ARG PRESTODB_REPOSITORY=https://github.com/prestodb/presto
ARG PRESTODB_CHECKOUT=origin/master

USER root:root

ENV CPU_TARGET=${CPU_TARGET}
ENV TZ=Europe/Warsaw

ENV CC=/opt/rh/gcc-toolset-9/root/bin/gcc
ENV CXX=/opt/rh/gcc-toolset-9/root/bin/g++

ENV PRESTODB_HOME=/opt/presto
ENV DEPENDENCY_DIR=/opt/dependency/adapter-deps
ENV PROMPT_ALWAYS_RESPOND=n

ENV PATH=${DEPENDENCY_DIR}/install/bin:${DEPENDENCY_DIR}/install/bin/hadoop-2.10.1/bin:$PATH

ENV PRESTO_ENABLE_PARQUET=ON
ENV PRESTO_ENABLE_S3=ON
ENV PRESTO_ENABLE_HDFS=ON
ENV PRESTO_ENABLE_TESTING=ON
ENV CLEANUP_BUILD_ARTIFACTS=1

SHELL ["/bin/bash", "-c"]
WORKDIR ${PRESTODB_HOME}
#-----------------------------------------------------------
#---( START of PrestoDB and Velox dependency tree build scripts
#-----------------------------------------------------------
RUN set -exu && \
    dnf -y install git wget unzip pkg-config python3-devel java clang-tools-extra && \
    git clone --progress ${PRESTODB_REPOSITORY} "${PRESTODB_HOME}/_repo" && \
    git -C "${PRESTODB_HOME}/_repo" checkout "${PRESTODB_CHECKOUT}" && \
    make --directory="${PRESTODB_HOME}/_repo/presto-native-execution" submodules && \
    mkdir -p "${DEPENDENCY_DIR}/install/bin" \
             "${PRESTODB_HOME}/_repo/presto-native-execution/_build/release" \
             "${PRESTODB_HOME}/catalog" \
             "${PRESTODB_HOME}/tests" && \
    bash "${PRESTODB_HOME}/_repo/presto-native-execution/velox/scripts/setup-circleci.sh" && \
    bash "${PRESTODB_HOME}/_repo/presto-native-execution/scripts/setup-centos.sh" && \
#-----------------------------------------------------------
#---( START wget valid antlr java runtime
#-----------------------------------------------------------
    wget -q 'https://www.antlr.org/download/antlr-4.9.3-complete.jar' -O '/usr/local/lib/antlr-4.9.3-complete.jar' && \
    printf '#!/usr/bin/bash\n\njava -jar /usr/local/lib/antlr-4.9.3-complete.jar "$@"' > '/usr/local/bin/antlr' && \
    chmod +x "/usr/local/bin/antlr" && \
    dnf clean all
#-----------------------------------------------------------
#---( START of PrestoCpp and Velox main build process
#-----------------------------------------------------------
RUN source /opt/rh/gcc-toolset-9/enable && \
    set -exu && \
    bash "${PRESTODB_HOME}/_repo/presto-native-execution/velox/scripts/setup-adapters.sh" && \
    make --directory="${PRESTODB_HOME}/_repo/presto-native-execution" release PRESTO_ENABLE_PARQUET=ON PRESTO_ENABLE_S3=ON PRESTO_ENABLE_HDFS=ON && \
#-----------------------------------------------------------
#---( START of clean-up artifacts task
#-----------------------------------------------------------
    [ ${CLEANUP_BUILD_ARTIFACTS} -eq 0 ] || \
    ( \
      rm -rf $(find "${PRESTODB_HOME}/_repo/presto-native-execution/_build/release" | grep -E '\.o$|\.cpp$|\.tcc$|\.h$|CMakeFiles|\.cmake$|\.cs$|\.rb$|\.cc$|\.R$|\.c$|\.hpp$|\.rb$') && \
      rm -rf $(find "${PRESTODB_HOME}/_repo/presto-native-execution/_build/release" | grep -E '\.ninja_deps|\.ninja_log|\.ninja|CMakeCache|\.tcl') \
    ) && \
    ( \
      mv ${PRESTOCPP_HOME}/_build/release/presto_cpp/main/* ${PRESTOCPP_HOME} && \
      mv ${PRESTOCPP_HOME}/_build/release/presto_cpp/presto_protocol/tests/presto_protocol_test ${PRESTOCPP_HOME}/tests || true \
    ) && \
    [ ${CLEANUP_BUILD_ARTIFACTS} -eq 0 ] || \
    rm -rf ${PRESTOCPP_HOME}/_repo /opt/dependency/aws-sdk-cpp /tmp/* && \
    dnf clean all

#============================================================
#---) END of PrestoCpp and Velox main build process
#============================================================
# /////////////////////////////////
#    RUNTIME TASK DEFINITION
# /////////////////////////////////
#============================================================
ARG BASE_IMAGE=quay.io/centos/centos:stream8
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="Prestissimo" \
      org.opencontainers.image.description="Prestissimo Runtime Docker image" \
      org.opencontainers.image.version="1.0.0"

ARG PRESTO_UID=186

SHELL ["/bin/bash", "-c"]
ENV PRESTO_HOME="/opt/presto/"
WORKDIR /opt/presto/

COPY opt/ /opt/
COPY etc/ /opt/presto/etc/

COPY --from=build-stage /usr/lib64/lib* /usr/local/lib64/
COPY --from=build-stage /usr/local/lib/libhdfs3* /usr/local/lib/
COPY --from=build-stage /opt/presto/ /opt/presto/

RUN set -exu && \
    dnf -y install uuid hostname vim && \
    #---( INFO create a system account (-r) and same name group (-U) with UID and home path at /opt (-d) named presto
    useradd -r -U --uid=${PRESTO_UID} -d /opt presto && \
    chgrp ${PRESTO_UID} /etc/passwd && \
    chown -R ${PRESTO_UID} /usr/local /opt && \
    chmod -R ug+rw /etc/passwd /opt && \
    chmod ug+x /opt/*.sh /opt/presto/presto_server && \
    rm -rf /root/.cache /tmp && \
    dnf clean all

USER ${PRESTO_UID}

ENTRYPOINT [ "/opt/entrypoint.sh" ]

EXPOSE 22 8080

#============================================================
# /////////////////////////////////
#  END OF RUNTIME TASK DEFINITION
# /////////////////////////////////
#============================================================
