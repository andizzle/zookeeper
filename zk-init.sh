#!/bin/sh

export PATH=/opt/zookeeper/bin:$PATH

MYID=$1
ZK=$2

HOSTNAME=`hostname`
#IPADDRESS=`grep $HOSTNAME /etc/hosts | awk {'print $1'}`
IPADDRESS=`/sbin/ip route|awk '/eth1/ { print $9 }'`

if [ -n "$ZK" ]
then
    # join an existing cluster
    echo "`/opt/zookeeper/bin/zkCli.sh -server $ZK:2181 get /zookeeper/config|grep ^server`" >> /opt/zookeeper/conf/zoo.cfg.dynamic
    echo "server.$MYID=$IPADDRESS:2888:3888:observer;2181" >> /opt/zookeeper/conf/zoo.cfg.dynamic
    cp /opt/zookeeper/conf/zoo.cfg.dynamic /opt/zookeeper/conf/zoo.cfg.dynamic.org
    /opt/zookeeper/bin/zkServer-initialize.sh --force --myid=$MYID
    ZOO_LOG_DIR=/var/log ZOO_LOG4J_PROP='INFO,CONSOLE,ROLLINGFILE' /opt/zookeeper/bin/zkServer.sh start
    /opt/zookeeper/bin/zkCli.sh -server $ZK:2181 reconfig -add "server.$MYID=$IPADDRESS:2888:3888:participant;2181"
    /opt/zookeeper/bin/zkServer.sh stop
    ZOO_LOG_DIR=/var/log ZOO_LOG4J_PROP='INFO,CONSOLE,ROLLINGFILE' /opt/zookeeper/bin/zkServer.sh start-foreground
else
    # start a new cluster
    echo "server.$MYID=$IPADDRESS:2888:3888;2181" >> /opt/zookeeper/conf/zoo.cfg.dynamic
    /opt/zookeeper/bin/zkServer-initialize.sh --force --myid=$MYID
    ZOO_LOG_DIR=/var/log ZOO_LOG4J_PROP='INFO,CONSOLE,ROLLINGFILE' /opt/zookeeper/bin/zkServer.sh start-foreground
fi
