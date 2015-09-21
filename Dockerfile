FROM ubuntu:15.10

RUN apt-get update && \
apt-get install -y curl openjdk-8-jdk git ant && \
apt-get clean

RUN git clone https://github.com/apache/zookeeper.git /opt/zookeeper

WORKDIR /opt/zookeeper

RUN git checkout release-3.5.1
RUN ant jar
RUN cp ./conf/zoo_sample.cfg ./conf/zoo.cfg
RUN echo "standaloneEnabled=false" >> ./conf/zoo.cfg
RUN echo "dynamicConfigFile=/opt/zookeeper/conf/zoo.cfg.dynamic" >> ./conf/zoo.cfg

ADD zk-init.sh /usr/local/bin/
#ENTRYPOINT ["zk-init.sh"]
