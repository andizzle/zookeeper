#!/bin/bash

set -e

ZK=$2
MYID=$3

HOSTNAME=`hostname`
IPADDRESS=`/sbin/ip route|awk '/eth1/ { print $9 }'`

RE="^[0-9]+$"

# config single or cluster
function config {
    if [ -n "$ZK" ]; then
        # join an existing cluster

        echo "`bin/zkCli.sh -server $ZK:2181 get /zookeeper/config|grep ^server`" >> conf/zoo.cfg.dynamic

        # if no MYID specified, pick one
        if ! [[ $MYID =~ $RE ]]; then
            # get all participants' id
            ids=$(cat conf/zoo.cfg.dynamic | grep -Eo '[0-9]{1,3}=' | awk -F'=' '{print $1}')
            MYID=$(next_id "${ids[*]}")
        fi

        echo "server.$MYID=$IPADDRESS:2888:3888:observer;2181" >> conf/zoo.cfg.dynamic
        cp conf/zoo.cfg.dynamic conf/zoo.cfg.dynamic.org
    else
        # start a new cluster
        if ! [[ $MYID =~ $RE ]]; then
            MYID=1
        fi
        echo "server.$MYID=$IPADDRESS:2888:3888;2181" >> conf/zoo.cfg.dynamic
    fi
    bin/zkServer-initialize.sh --configfile=/opt/zookeeper/conf/zoo.cfg --force --myid=$MYID
}

# config follower when join a cluster
function config_follower {
    if [ -n "$ZK" ]; then
        ZOO_LOG_DIR=/var/log ZOO_LOG4J_PROP='INFO,CONSOLE,ROLLINGFILE' bin/zkServer.sh start
        bin/zkCli.sh -server $ZK:2181 reconfig -add "server.$MYID=$IPADDRESS:2888:3888:participant;2181"
        bin/zkServer.sh stop
    fi
}

# id generate
function next_id {
    next_id=1
    ids=$1

    while [ "$next_id" -lt 256 ]; do
        exist=false

        for id in ${ids[*]}; do
            if [ "$next_id" -eq "$id" ]; then
                exist=true
                break
            fi
        done

        if ! $exist; then
            break
        else
            let "next_id++"
        fi
    done
    echo $next_id
}

# start the zookeeper if the param is an id
if ! [ -n "$1" ] || [ "$1" = 'init' ]; then

    cd /opt/zookeeper

    config

    config_follower

    ZOO_LOG_DIR=/var/log ZOO_LOG4J_PROP='INFO,CONSOLE,ROLLINGFILE' /opt/zookeeper/bin/zkServer.sh --config /opt/zookeeper/conf start-foreground

fi

exec "$@"
