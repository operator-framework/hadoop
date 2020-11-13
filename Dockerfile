FROM centos:8.1.1911 as build

# Install runtime deps only.
RUN dnf -y update
RUN dnf -y install keyutils-libs krb5-libs libcom_err libgcc libselinux libstdc++ libtirpc openssl-libs pcre2 snappy \
    which zlib sudo

# * Install development tools such as GCC, autotools, OpenJDK
RUN dnf -y group install --with-optional 'Development Tools'
RUN dnf -y install java-1.8.0-openjdk-devel

# * Install libraries provided by CentOS 8.
RUN dnf -y install libtirpc-devel zlib-devel lz4-devel bzip2-devel openssl-devel cyrus-sasl-devel libpmem-devel

# * Install optional dependencies (snappy-devel).
RUN dnf -y --enablerepo=PowerTools install snappy-devel

# * Install optional dependencies (libzstd-devel).
RUN dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
RUN dnf -y --enablerepo=epel install libzstd-devel

# * Install optional dependencies (isa-l).
RUN dnf -y --enablerepo=PowerTools install nasm

# * Install findbugs
RUN curl -L -o harbottle-main-release.rpm https://harbottle.gitlab.io/harbottle-main/8/x86_64/harbottle-main-release.rpm
RUN rpm -Uvh harbottle-main-release.rpm
RUN dnf -y install sonarqube-findbugs

RUN dnf clean all

ENV FINDBUGS_HOME /usr
ENV CMAKE_C_COMPILER=gcc CMAKE_CXX_COMPILER=g++

######
# Install cmake 3.1.0
######
RUN curl -L -o cmake-3.1.0-Linux-x86_64.sh https://github.com/Kitware/CMake/releases/download/v3.1.0/cmake-3.1.0-Linux-x86_64.sh
RUN chmod u+x cmake-3.1.0-Linux-x86_64.sh
RUN ./cmake-3.1.0-Linux-x86_64.sh --prefix=/usr/local --skip-license
RUN sudo ln -fs /usr/local/bin/cmake /usr/bin/cmake3
RUN cmake --version
RUN cmake3 --version

######
# Install Google Protobuf 3.7.1
######
RUN mkdir -p /opt/protobuf-src \
    && curl -L -s -S \
      https://github.com/protocolbuffers/protobuf/releases/download/v3.7.1/protobuf-java-3.7.1.tar.gz \
      -o /opt/protobuf.tar.gz \
    && tar xzf /opt/protobuf.tar.gz --no-same-owner --strip-components 1 -C /opt/protobuf-src \
    && cd /opt/protobuf-src \
    && ./configure --prefix=/opt/protobuf \
    && make install \
    && cd /root \
    && rm -rf /opt/protobuf-src
ENV PROTOBUF_HOME /opt/protobuf
ENV PATH "${PATH}:/opt/protobuf/bin"
RUN protoc --version

######
# Install Apache Maven 3.3.9
######
RUN curl -L -o apache-maven-3.3.9-bin.tar.gz http://www.eu.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
RUN tar xzf apache-maven-3.3.9-bin.tar.gz
RUN mkdir /usr/local/maven
RUN mv apache-maven-3.3.9/ /usr/local/maven/
RUN alternatives --install /usr/bin/mvn mvn /usr/local/maven/apache-maven-3.3.9/bin/mvn 1
RUN rm apache-maven-3.3.9-bin.tar.gz
RUN mvn --version

RUN mkdir /build
WORKDIR /build

COPY hadoop-yarn-project /build/hadoop-yarn-project
COPY hadoop-assemblies /build/hadoop-assemblies
COPY hadoop-project /build/hadoop-project
COPY hadoop-common-project /build/hadoop-common-project
COPY hadoop-cloud-storage-project /build/hadoop-cloud-storage-project
COPY hadoop-project-dist /build/hadoop-project-dist
COPY hadoop-maven-plugins /build/hadoop-maven-plugins
COPY hadoop-dist /build/hadoop-dist
COPY hadoop-minicluster /build/hadoop-minicluster
COPY hadoop-mapreduce-project /build/hadoop-mapreduce-project
COPY hadoop-tools /build/hadoop-tools
COPY hadoop-hdfs-project /build/hadoop-hdfs-project
COPY hadoop-client-modules /build/hadoop-client-modules
COPY hadoop-build-tools /build/hadoop-build-tools
COPY dev-support /build/dev-support
COPY pom.xml /build/pom.xml
COPY LICENSE.txt /build/LICENSE.txt
COPY licenses /build/licenses
COPY LICENSE-binary /build/LICENSE-binary
COPY licenses-binary /build/licenses-binary
COPY BUILDING.txt /build/BUILDING.txt
COPY NOTICE.txt /build/NOTICE.txt
COPY NOTICE-binary /build/NOTICE-binary
COPY README.txt /build/README.txt

# build hadoop
RUN mvn -B -e -Dtest=false -DskipTests -Dmaven.javadoc.skip=true package -Pdist,native -Dtar
# Install prometheus-jmx agent
RUN mvn dependency:copy -Dartifact=io.prometheus.jmx:jmx_prometheus_javaagent:0.3.1:jar -DoutputDirectory=/build \
            -Dmdep.stripVersion
# Get gcs-connector for Hadoop
RUN mvn dependency:copy -Dartifact=com.google.cloud.bigdataoss:gcs-connector:hadoop3-2.1.3:jar:shaded \
    -DoutputDirectory=/build -Dmdep.stripVersion

FROM centos:8.1.1911

# In order to avoid a potential `faq` and `jq` conflict using yum, curl the binary
# from Github and move to /usr/local/bin
ARG LATEST_RELEASE=0.0.6
RUN curl -Lo /usr/local/bin/faq https://github.com/jzelinskie/faq/releases/download/$LATEST_RELEASE/faq-linux-amd64 \
    && chmod +x /usr/local/bin/faq

RUN set -x; yum install --setopt=skip_missing_names_on_install=False -y \
    java-1.8.0-openjdk \
    java-1.8.0-openjdk-devel \
    epel-release \
    curl \
    less  \
    procps \
    net-tools \
    bind-utils \
    which \
    rsync \
    openssl \
    && yum clean all \
    && rm -rf /tmp/* /var/tmp/*

ENV TINI_VERSION v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/bin/tini
RUN chmod +x /usr/bin/tini

ENV JAVA_HOME=/etc/alternatives/jre

ENV HADOOP_VERSION 3.3.0

ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_LOG_DIR=$HADOOP_HOME/logs
ENV HADOOP_CLASSPATH=$HADOOP_HOME/share/hadoop/tools/lib/*
ENV HADOOP_CONF_DIR=/etc/hadoop
ENV PROMETHEUS_JMX_EXPORTER /opt/jmx_exporter/jmx_exporter.jar
ENV PATH=$HADOOP_HOME/bin:$PATH

COPY --from=build /build/hadoop-dist/target/hadoop-$HADOOP_VERSION $HADOOP_HOME
COPY --from=build /build/jmx_prometheus_javaagent.jar $PROMETHEUS_JMX_EXPORTER
COPY --from=build /build/gcs-connector-shaded.jar $HADOOP_HOME/share/hadoop/tools/lib/gcs-connector-shaded.jar

WORKDIR $HADOOP_HOME

# remove unnecessary doc/src files
RUN rm -rf ${HADOOP_HOME}/share/doc \
    && for dir in common hdfs mapreduce tools yarn; do \
    rm -rf ${HADOOP_HOME}/share/hadoop/${dir}/sources; \
    done \
    && rm -rf ${HADOOP_HOME}/share/hadoop/common/jdiff \
    && rm -rf ${HADOOP_HOME}/share/hadoop/mapreduce/lib-examples \
    && rm -rf ${HADOOP_HOME}/share/hadoop/yarn/test \
    && find ${HADOOP_HOME}/share/hadoop -name *test*.jar | xargs rm -rf

RUN ln -s $HADOOP_HOME/etc/hadoop $HADOOP_CONF_DIR
RUN mkdir -p $HADOOP_LOG_DIR

# https://docs.oracle.com/javase/7/docs/technotes/guides/net/properties.html
# Java caches dns results forever, don't cache dns results forever:
RUN sed -i '/networkaddress.cache.ttl/d' $JAVA_HOME/lib/security/java.security
RUN sed -i '/networkaddress.cache.negative.ttl/d' $JAVA_HOME/lib/security/java.security
RUN echo 'networkaddress.cache.ttl=0' >> $JAVA_HOME/lib/security/java.security
RUN echo 'networkaddress.cache.negative.ttl=0' >> $JAVA_HOME/lib/security/java.security

# imagebuilder expects the directory to be created before VOLUME
RUN mkdir -p /hadoop/dfs/data /hadoop/dfs/name

# to allow running as non-root
RUN chown -R 1002:0 $HADOOP_HOME /hadoop $HADOOP_CONF_DIR $JAVA_HOME/lib/security/cacerts && \
    chmod -R 774 $HADOOP_HOME /hadoop $HADOOP_CONF_DIR $JAVA_HOME/lib/security/cacerts

VOLUME /hadoop/dfs/data /hadoop/dfs/name

USER 1002

LABEL io.k8s.display-name="OpenShift Hadoop" \
    io.k8s.description="This is an image used by the Metering Operator to to install and run HDFS." \
    summary="This is an image used by the Metering Operator to to install and run HDFS." \
    io.openshift.tags="openshift" \
    maintainer="<metering-team@redhat.com>"
