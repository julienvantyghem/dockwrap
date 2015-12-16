#!/bin/bash

function container_state() {
  docker inspect --format '{{ .State.Running }}' $1 2>/dev/null
}

function container_args() {
  docker inspect --format '{{ .Args }}' $1 2>/dev/null
}

function ip_pattern() {
  echo "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"
}

function propose_service() {
  echo -n -e "Do you want me to $1 for you?"
  read -p " [y/n] " -n 1 -r
  echo    # (optional) move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1
  fi
}

function skydns_nameserver() {
  echo $(container_args $1) | grep -oE "\-nameserver $(ip_pattern)" | grep -oE $(ip_pattern)
}

function is_nameserver_up() {
  dig +time=1 @$1 google.com &> /dev/null && echo "true" || echo "false"
}

function spawn_container() {
  echo "Calling spawn_container with arguments $@"
  IMAGE=$1
  CONTAINER=$2
  RUN_OPTIONS=$3
  RUN_CMD=$4
  RUNNING=$(container_state $CONTAINER)
  if [ "$RUNNING" == "" ]; then
    echo "$CONTAINER does not exist"
    if [ -n "$(docker images -q $IMAGE 2> /dev/null)" ]; then
      if propose_service "spawn it from $IMAGE"; then
        docker run $RUN_OPTIONS $IMAGE $RUN_CMD
        spawn_container "$IMAGE" "$CONTAINER" "$RUN_OPTIONS" "$RUN_CMD"
      else
        echo "I can't do anything without a running container"
        exit 0
      fi
    else
      echo "Image $IMAGE doesn't exist"
      if propose_service "pull it"; then
        docker pull $IMAGE
        spawn_container "$IMAGE" "$CONTAINER" "$RUN_OPTIONS" "$RUN_CMD"
      else
        echo "I can't do anything without an image"
        exit 0
      fi
    fi
  elif [ "$RUNNING" == "true" ]; then
    echo "$CONTAINER is running smoothly"
  else
    echo "$CONTAINER is currently stopped"
    if propose_service "start it"; then
      docker start $CONTAINER
      spawn_container "$IMAGE" "$CONTAINER" "$RUN_OPTIONS" "$RUN_CMD"
    else
      echo "I can't do anything without a running container"
      exit 0
    fi
  fi
}

# This function is not used for the time being
function check_skydns_forward_nameserver() {
  FWD_NS=$(skydns_nameserver $SKYDNS_CONTAINER)
  if [ "$(is_nameserver_up $FWD_NS)" == "true" ]; then
    echo "$SKYDNS_CONTAINER is running smoothly, now make sure that your network interface uses it as primary DNS server"
    propose_service ""
  else
    echo "Forward nameserver $FWD_NS does not seem to be working"
    propose_service "restart $SKYDNS_CONTAINER with a new nameserver?"
    echo "I lied, I got nothing (for the moment)"
  fi
}

spawn_container "docker.io/crosbymichael/skydns" "skydns" "-d --name skydns -p 127.0.0.1:53:53/udp --restart=always" "-nameserver 192.168.41.164:53 -domain docker"
spawn_container "docker.io/crosbymichael/skydock" "skydock" "-d -v /var/run/docker.sock:/docker.sock --name skydock --restart=always" "-ttl 10000000 -environment dev -s /docker.sock -domain docker -name skydns"
