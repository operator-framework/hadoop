#!/bin/bash -x

set -eo pipefail

# $1=OPENSHIFT_CI=true means running in CI
if [[ "$1" == "true" ]]; then
  yum -y install --setopt=skip_missing_names_on_install=False \
      curl \
      java-1.8.0-openjdk-devel \
      java-1.8.0-openjdk \
      protobuf protobuf-compiler \
      patch \
      git \
      lzo-devel zlib-devel gcc gcc-c++ make autoconf automake libtool openssl-devel fuse-devel \
      cmake3 \
      && yum clean all \
      && rm -rf /var/cache/yum

  pushd /tmp
  curl -o maven.tgz https://downloads.apache.org/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
  tar zxvf maven.tgz
  export M2_HOME=/tmp/apache-maven-3.3.9
  export PATH=${PATH}:${M2_HOME}/bin
  popd

  test -e /usr/bin/cmake || ln -s /usr/bin/cmake3 /usr/bin/cmake
  export CMAKE_C_COMPILER=gcc CMAKE_CXX_COMPILER=g++

  # Build hadoop
  cd /build && mvn -B -e -Dtest=false -DskipTests -Dmaven.javadoc.skip=true clean package -Pdist,native -Dtar
  # Install prometheus-jmx agent
  mvn dependency:get -Dartifact=io.prometheus.jmx:jmx_prometheus_javaagent:0.3.1:jar -Ddest=/build/jmx_prometheus_javaagent.jar && mv $HOME/.m2/repository/io/prometheus/jmx/jmx_prometheus_javaagent/0.3.1/jmx_prometheus_javaagent-0.3.1.jar /build/jmx_prometheus_javaagent.jar

  # Get gcs-connector for Hadoop
  cd /build && mvn dependency:get -Dartifact=com.google.cloud.bigdataoss:gcs-connector:hadoop3-2.0.0-RC2:jar:shaded && mv $HOME/.m2/repository/com/google/cloud/bigdataoss/gcs-connector/hadoop3-2.0.0-RC2/gcs-connector-hadoop3-2.0.0-RC2-shaded.jar /build/gcs-connector-hadoop3-2.0.0-RC2-shaded.jar
else
  echo "ART build is running"
  # Otherwise this is a production brew build by ART
  yum -y install curl \
    && yum clean all \
    && rm -rf /var/cache/yum
  export RH_HADOOP_PATCH_VERSION=00002
  export HADOOP_VERSION=3.1.1

  export HADOOP_RELEASE_URL=http://download.eng.bos.redhat.com/brewroot/packages/org.apache.hadoop-hadoop-main/${HADOOP_VERSION}.redhat_${RH_HADOOP_PATCH_VERSION}/1/maven/org/apache/hadoop/hadoop-dist/${HADOOP_VERSION}.redhat-${RH_HADOOP_PATCH_VERSION}/hadoop-dist-${HADOOP_VERSION}.redhat-${RH_HADOOP_PATCH_VERSION}-bin.tar.gz
  export HADOOP_OUT=/build/hadoop-dist/target/hadoop-$HADOOP_VERSION

  curl -fSLs \
      $HADOOP_RELEASE_URL \
      -o /tmp/hadoop-dist-bin.tar.gz

  mkdir -p $(dirname $HADOOP_OUT) && \
      tar -xvf /tmp/hadoop-dist-bin.tar.gz -C /tmp \
      && mv /tmp/hadoop-${HADOOP_VERSION}.redhat-${RH_HADOOP_PATCH_VERSION}/ \
      $HADOOP_OUT

  export PROMETHEUS_JMX_EXPORTER_VERSION=0.3.1
  export RH_PROMETHEUS_JMX_EXPORTER_PATCH_VERSION=00006
  export RH_PROMETHEUS_JMX_EXPORTER_VERSION=${PROMETHEUS_JMX_EXPORTER_VERSION}.redhat-${RH_PROMETHEUS_JMX_EXPORTER_PATCH_VERSION}
  export RH_PROMETHEUS_JMX_EXPORTER_BREW_DIR=${PROMETHEUS_JMX_EXPORTER_VERSION}.redhat_${RH_PROMETHEUS_JMX_EXPORTER_PATCH_VERSION}
  export PROMETHEUS_JMX_EXPORTER_OUT=/build/jmx_prometheus_javaagent.jar
  export PROMETHEUS_JMX_EXPORTER_URL=http://download.eng.bos.redhat.com/brewroot/packages/io.prometheus.jmx-parent/${RH_PROMETHEUS_JMX_EXPORTER_BREW_DIR}/1/maven/io/prometheus/jmx/jmx_prometheus_javaagent/${RH_PROMETHEUS_JMX_EXPORTER_VERSION}/jmx_prometheus_javaagent-${RH_PROMETHEUS_JMX_EXPORTER_VERSION}.jar

  set -x; curl -fSLs \
      $PROMETHEUS_JMX_EXPORTER_URL \
      -o $PROMETHEUS_JMX_EXPORTER_OUT

  export GOOGLE_BIGDATA_OSS_VERSION=1.9.17
  export RH_GOOGLE_BIGDATA_OSS_PATCH_VERSION=00002
  export RH_GOOGLE_BIGDATA_OSS_BREW_DIR=${GOOGLE_BIGDATA_OSS_VERSION}.redhat_${RH_GOOGLE_BIGDATA_OSS_PATCH_VERSION}
  export RH_GCS_CONNECTOR_PATCH_VERSION=00001
  export RH_GCS_CONNECTOR_VERSION=${GOOGLE_BIGDATA_OSS_VERSION}.hadoop3-redhat-${RH_GCS_CONNECTOR_PATCH_VERSION}
  export GCS_CONNECTOR_OUT=/build/gcs-connector-hadoop3-shaded.jar

  export GCS_CONNECTOR_URL=http://download.eng.bos.redhat.com/brewroot/packages/com.google.cloud.bigdataoss-bigdataoss-parent/${RH_GOOGLE_BIGDATA_OSS_BREW_DIR}/1/maven/com/google/cloud/bigdataoss/gcs-connector/${RH_GCS_CONNECTOR_VERSION}/gcs-connector-${RH_GCS_CONNECTOR_VERSION}-shaded.jar

  set -x; curl -fSLs \
      $GCS_CONNECTOR_URL \
      -o $GCS_CONNECTOR_OUT
fi
