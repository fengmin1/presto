# prestissimo/build

# /////////////////////////////////
#    BUILD TASK START
# /////////////////////////////////
#============================================================
#---( START of build-stage container definition

ARG IMAGE_NAME="prestissimo"
ARG IMAGE_TAG="latest"
ARG IMAGE_REGISTRY=""
FROM ${IMAGE_REGISTRY}${IMAGE_NAME}-base:${IMAGE_TAG} AS build-stage

#---( START Defaults that can be overriden form cmd line - can be used for templating

ARG CLEANUP_BUILD_ARTIFACTS=1

ARG PRESTODB_REPOSITORY=https://github.com/prestodb/presto
ARG PRESTODB_CHECKOUT=origin/master

ARG PRESTODB_HOME=/opt/presto
ARG PRESTOCPP_HOME=${PRESTODB_HOME}/_repo/presto-native-execution
ARG VELOX_MOD_HOME=${PRESTOCPP_HOME}/velox

#---) END Defaults that can be overriden form cmd line
#-----------------------------------------------------------
#---( START List of Presto and Velox modules to enable

ARG MAVEN_JAVA_OPTS=""

ARG PRESTO_ENABLE_PARQUET=ON
ARG PRESTO_ENABLE_S3=ON
ARG PRESTO_ENABLE_HDFS=ON
ARG PRESTO_ENABLE_TESTING=ON

ARG VELOX_ENABLE_ARROW=ON
ARG VELOX_ENABLE_EXPRESSION=ON

#---) END List of Presto and Velox modules to enable
#-----------------------------------------------------------
#---( START other variables and evironment settings

ENV TREAT_WARNINGS_AS_ERRORS=0
ENV CMAKE_PREFIX_PATH=/usr/local

ENV MAVEN_OPTS=" -Xmx16G -XX:+ExitOnOutOfMemoryError -Djava.net.useSystemProxies=true ${MAVEN_JAVA_OPTS} "
ENV DEPENDENCY_DIR=${DEPENDENCY_DIR}

ENV PRESTO_HOME="${PRESTODB_HOME}/_repo"
ENV CLASSPATH=".:/usr/local/lib/antlr-4.9.3-complete.jar:$CLASSPATH"

ENV CC=/opt/rh/gcc-toolset-9/root/bin/gcc
ENV CXX=/opt/rh/gcc-toolset-9/root/bin/g++

SHELL ["/bin/bash", "-c"]

#---) END of other variables
#============================================================
#---( START build tools selection and exit on errors flags selection
WORKDIR ${PRESTODB_HOME}
RUN source /opt/rh/gcc-toolset-9/enable && \
    set -exu && \
#---) END build tools selection
#-----------------------------------------------------------
#---( START of basic directory creation, repository preparation and build adapters
    mkdir -p "${ADAPTER_DEPENDENCY_DIR}/install/bin" && \
    git clone ${PRESTODB_REPOSITORY} ${PRESTODB_HOME}/_repo && \
    cd ${PRESTODB_HOME}/_repo && \
    git checkout ${PRESTODB_CHECKOUT} && \
    cd ${PRESTOCPP_HOME} && \
    make submodules && \
    cp "${PRESTODB_HOME}/_repo/license.header" "${PRESTOCPP_HOME}/license.header" && \
    chmod +x "${VELOX_MOD_HOME}/scripts/setup-adapters.sh" && \
    PROMPT_ALWAYS_RESPOND=n DEPENDENCY_DIR=${ADAPTER_DEPENDENCY_DIR} ${VELOX_MOD_HOME}/scripts/setup-adapters.sh && \
    rm -rf /tmp/*
#---) END OF preparation
#-----------------------------------------------------------
#---( START of main build release task with all dependencies
WORKDIR ${PRESTOCPP_HOME}
RUN source /opt/rh/gcc-toolset-9/enable && \
    set -exu && \
    source "${VELOX_MOD_HOME}/scripts/setup-helper-functions.sh" && \
    CPU_TARGET="${CPU_TARGET:-avx}" && \
    COMPILER_FLAGS=$(get_cxx_flags $CPU_TARGET) && \
    mkdir -p _build/release && \
    cmake -B _build/release -GNinja \
            -DENABLE_ALL_WARNINGS=1 \
            -DCMAKE_PREFIX_PATH="/usr/local" \
            -DCMAKE_BUILD_TYPE=release \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
            -DCMAKE_CXX_STANDARD=17 \
            -DCMAKE_CXX_FLAGS="$COMPILER_FLAGS" \
            -DPRESTO_ENABLE_PARQUET=${PRESTO_ENABLE_PARQUET} \
            -DPRESTO_ENABLE_HDFS=${PRESTO_ENABLE_HDFS} \
            -DPRESTO_ENABLE_S3=${PRESTO_ENABLE_S3} \
            -DPRESTO_ENABLE_TESTING=${PRESTO_ENABLE_TESTING} \
            -DVELOX_ENABLE_DUCKDB=ON \
            -DVELOX_ENABLE_EXEC=ON \
            -DVELOX_ENABLE_AGGREGATES=ON \
            -DVELOX_ENABLE_HIVE_CONNECTOR=ON \
            -DVELOX_ENABLE_TPCH_CONNECTOR=ON \
            -DVELOX_ENABLE_PRESTO_FUNCTIONS=ON \
            -DVELOX_ENABLE_SPARK_FUNCTIONS=ON \
            -DVELOX_ENABLE_EXPRESSION=ON \
            -DVELOX_ENABLE_PARSE=ON \
            -DVELOX_ENABLE_SUBSTRAIT=ON \
            -DVELOX_ENABLE_BENCHMARKS=OFF \
            -DVELOX_ENABLE_BENCHMARKS_BASIC=OFF \
            -DVELOX_ENABLE_ARROW=${VELOX_ENABLE_ARROW} \
            -DVELOX_BUILD_MINIMAL=OFF \
            -DVELOX_BUILD_TESTING=${PRESTO_ENABLE_TESTING} \
            -DVELOX_BUILD_TEST_UTILS=${PRESTO_ENABLE_TESTING} \
            -DVELOX_ENABLE_EXAMPLES=OFF \
            -DAWSSDK_ROOT_DIR="${ADAPTER_DEPENDENCY_DIR}/install" \
            -GNinja \
            -DMAX_LINK_JOBS=16 \
            -DMAX_HIGH_MEM_JOBS=32 && \
    ninja -C _build/release -j 32 && \
    rm -rf /tmp/*
#---) END of main build release task with all dependencies

#---( START of all clean-up task - (based on CLEANUP_BUILD_ARTIFACTS)
WORKDIR /opt/presto/
RUN set -exu && \
    mkdir -p /opt/presto/catalog /opt/presto/tests && \
    cd ${PRESTOCPP_HOME}/_build/release && \
    ( [ ${CLEANUP_BUILD_ARTIFACTS} -eq 0 ] || rm -rf $(find | grep -E '\.o$|\.cpp$|\.tcc$|\.h$|CMakeFiles|\.cmake$|\.cs$|\.rb$|\.cc$|\.R$|\.c$|\.hpp$|\.rb$') ) && \
    ( [ ${CLEANUP_BUILD_ARTIFACTS} -eq 0 ] || rm -rf $(find | grep -E '\.ninja_deps|\.ninja_log|\.ninja|CMakeCache|\.tcl') ) && \
    mv ${PRESTOCPP_HOME}/_build/release/presto_cpp/main/* /opt/presto/ && \
    mv ${PRESTOCPP_HOME}/_build/release/presto_cpp/presto_protocol/tests/presto_protocol_test /opt/presto/tests || true && \
    ( [ ${CLEANUP_BUILD_ARTIFACTS} -eq 0 ] || rm -rf /opt/presto/_repo /opt/dependency/aws-sdk-cpp )
#---) END of all clean-up task

#---) END of build-stage container definition
#============================================================
# /////////////////////////////////
#    RUNTIME TASK DEFINITION
# /////////////////////////////////
#============================================================

ARG IMAGE_NAME="prestissimo"
ARG IMAGE_TAG="latest"
ARG IMAGE_REGISTRY=""
FROM ${IMAGE_REGISTRY}${IMAGE_NAME}-base:${IMAGE_TAG}

LABEL org.opencontainers.image.title="Prestissimo" \
      org.opencontainers.image.description="Prestissimo Runtime Docker image runtime" \
      org.opencontainers.image.version="1.0.0"

ARG PRESTO_UID=186

ENV PRESTO_HOME="/opt/presto/"

WORKDIR /opt/presto/

COPY opt/ /opt/
COPY --from=build-stage /usr/lib64/lib* /usr/local/lib64/
COPY --from=build-stage /usr/local/lib/libhdfs3* /usr/local/lib/
COPY --from=build-stage /opt/presto/ /opt/presto/
COPY etc/ /opt/presto/etc/

#---( INFO create a system account (-r) and same name group (-U) with UID and home path at /opt (-d) named presto
RUN useradd -r -U --uid=${PRESTO_UID} -d /opt presto && \
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
