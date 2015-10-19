#!/bin/bash

set -e

ZK=$2

IPADDRESS=`/sbin/ip route|awk '/eth1/ { print $9 }'`

RE="^[0-9]+$"

# config single or cluster
function config {
    if [ -n "$ZK" ]; then
        # join an existing cluster

        echo "`bin/zkCli.sh -server $ZK:2181 get /zookeeper/config|grep ^server`" >> conf/zoo.cfg.dynamic

        # get all participants' id
        ids=$(cat conf/zoo.cfg.dynamic | grep -Eo '[0-9]{1,3}=' | awk -F'=' '{print $1}')
        # always get new id
        MYID=$(next_id "${ids[*]}")

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
        fi
        let "next_id++"
    done
    echo $next_id
}

function prepareAWS {
    region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq --raw-output .region)
    if [[ ! $region ]]; then
        echo "$pkg: failed to get region"
        exit 1
    fi

    instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    if [[ ! $instance_id ]]; then
        echo "$pkg: failed to get instance id from instance metadata"
        exit 2
    fi

    instance_ip=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    if [[ ! $instance_ip ]]; then
        echo "$pkg: failed to get instance IP address"
        exit 3
    fi

    asg_name=$(aws autoscaling describe-auto-scaling-groups --region $region | jq --raw-output ".[] | map(select(.Instances[].InstanceId | contains(\"$ec2_instance_id\"))) | .[].AutoScalingGroupName")
    if [[ ! $asg_name ]]; then
        echo "$pkg: failed to get the auto scaling group name"
        exit 4
    fi

    peer_ips=$(aws ec2 describe-instances --region $region --instance-ids $(aws autoscaling describe-auto-scaling-groups --region $region --auto-scaling-group-name $asg_name | jq '.AutoScalingGroups[0].Instances[] | select(.LifecycleState  == "InService") | .InstanceId' | xargs) | jq -r ".Reservations[].Instances | map(.NetworkInterfaces[].PrivateIpAddress)[]")
    if [[ ! $peer_ips ]]; then
        echo "$pkg: unable to find members of auto scaling group"
        exit 5
    fi

    echo "zookeeper_peer_urls=$peer_ips"
}

case "$provider" in
    "aws")
        pkg="zookeeper-aws-cluster"
        prepareAWS
        ;;
    *)
        instance_ip=`/sbin/ip route|awk '/eth1/ { print $9 }'`
        ;;
esac

# start the zookeeper if the param is an id
if ! [ -n "$1" ] || [ "$1" = 'init' ]; then

    cd /opt/zookeeper

    config

    config_follower

    ZOO_LOG_DIR=/var/log ZOO_LOG4J_PROP='INFO,CONSOLE,ROLLINGFILE' /opt/zookeeper/bin/zkServer.sh --config /opt/zookeeper/conf start-foreground

fi

exec "$@"
