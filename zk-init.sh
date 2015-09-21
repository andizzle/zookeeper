#!/bin/bash

set -e

MYID=$1
ZK=$2

HOSTNAME=`hostname`
IPADDRESS=`/sbin/ip route|awk '/eth1/ { print $9 }'`

RE="^[0-9]+$"

function config {
    if [ -n "$ZK" ]; then
        # join an existing cluster
        echo "`bin/zkCli.sh -server $ZK:2181 get /zookeeper/config|grep ^server`" >> conf/zoo.cfg.dynamic
        echo "server.$MYID=$IPADDRESS:2888:3888:observer;2181" >> conf/zoo.cfg.dynamic
        cp conf/zoo.cfg.dynamic conf/zoo.cfg.dynamic.org
    else
        # start a new cluster
        echo "server.$MYID=$IPADDRESS:2888:3888;2181" >> conf/zoo.cfg.dynamic
    fi

    bin/zkServer-initialize.sh --configfile=/opt/zookeeper/conf/zoo.cfg --force --myid=$MYID
}

function config_follower {
    if [ -n "$ZK" ]; then
        ZOO_LOG_DIR=/var/log ZOO_LOG4J_PROP='INFO,CONSOLE,ROLLINGFILE' bin/zkServer.sh start
        bin/zkCli.sh -server $ZK:2181 reconfig -add "server.$MYID=$IPADDRESS:2888:3888:participant;2181"
        bin/zkServer.sh stop
    fi
}

# start the zookeeper if the param is an id
if [[ $MYID =~ $RE ]]; then

    cd /opt/zookeeper

    config

    config_follower

    ZOO_LOG_DIR=/var/log ZOO_LOG4J_PROP='INFO,CONSOLE,ROLLINGFILE' /opt/zookeeper/bin/zkServer.sh --config /opt/zookeeper/conf start-foreground

fi

exec "$@"
