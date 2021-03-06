#!/usr/bin/env bash
#
# Create a Swarm Mode service that builds an Elasticsearch, Kibana and cAdvisor
# cluster.
# This script is a mirror of the following gist, which is used to
# populate a Medium story. Unfortunately, there's no way to synchronize all
# three
#
# Medium: https://medium.com/contino-io/docker-kata-005-ac8429082f6c
# Gist: https://gist.github.com/anonymuse/df84df471abda00fbc3ab595037ab44d


# Set up global variables
swarm_network=${SWARM_NETWORK:-"monitoring"}
workers=${WORKERS:-"node01 node02 node03 node04"}
master=${MASTERS:-"master01"}
swarm_port=2377
master_ip=$(docker-machine ip ${master})
master_conf=$(docker-machine config ${master})


# Function to save configuration loading while we switch Docker Machine
# environment variables
# Arguments:
#   $@: the Docker engine commmand that we'll load into the configuration
swarm_master() {
      docker $master_conf $@
  }

# The body of our script
main() {


  # Create the network that we'll use for the swarm. Ensure that this command is
  # executed from your Swarm Manager.
  docker $master_conf network create $swarm_network -d overlay

  # Take the set of nodes, and get the first in the list
  # to use for the Elasticsearch node.
  worker_array=($workers)
  el_node=${worker_array[0]}

  # Create the Elasticsearch service
  docker $master_conf service create --network=$swarm_network \
    --mount type=volume,target=/usr/share/elasticsearch/data \
    --constraint node.hostname==$el_node \
    --name elasticsearch elasticsearch:2.4.0

  # Create the Kibana service
  docker $master_conf service create --network=$swarm_network \
    --name kibana -e ELASTICSEARCH_URL="http://elasticsearch:9200" \
    -p 5601:5601 kibana:4.6.0

  # Create the cAdivsor service
  docker $master_conf service create --network=$swarm_network \
    --mode global --name cadvisor \
    --mount type=bind,source=/,target=/rootfs,readonly=true \
    --mount type=bind,source=/var/run,target=/var/run,readonly=false \
    --mount type=bind,source=/sys,target=/sys,readonly=true \
    --mount type=bind,source=/var/lib/docker/,target=/var/lib/docker,readonly=true \
    google/cadvisor:latest -storage_driver=elasticsearch \
    -storage_driver_es_host="http://elasticsearch:9200"
  # Give the service time to start up
  echo "Sleeping for 10 seconds to allow cAdvisor service to initiate"
  sleep 10

  # Create a container visualizer
  docker $master_conf run -it -d -p 5000:5000 -e HOST=$master_ip -e PORT=5000 \
    -v /var/run/docker.sock:/var/run/docker.sock manomarks/visualizer

  # Open up a webpage to our visualizer
  open http://$master_ip:5000

  echo $master_conf

  # Add an index to Kibana for cAdvisor metrics
  docker $master_conf exec $(docker ${master_conf} ps |grep cadvisor | \
      awk '{print $1}' | head -1) apk --no-cache add curl

  docker $master_conf exec $(docker ${master_conf} ps |grep cadvisor | \
      awk '{print $1}' | head -1) curl -XPUT \
      http://elasticsearch:9200/.kibana/index-pattern/cadvisor -d \
      '{"title" : "cadvisor*", "timeFieldName": "container_stats.timestamp"}'

  # Make the index default
    docker $master_conf exec $(docker ${master_conf} ps |grep cadvisor | \
        awk '{print $1}' | head -1) curl -XPUT \
        http://elasticsearch:9200/.kibana/config/4.6.0 -d \
        '{"defaultIndex":"cadvisor"}'

}

main $@

