#!/usr/bin/env bash
#
# Purpose: Create a Swarm Mode cluster with a single master and a configurable
# number of workers.
# This script is a mirror of the following gist, which is used to
# populate a Medium story. Unfortunately, there's no way to synchronize all
# three
#
# Medium: https://medium.com/contino-io/docker-kata-005-ac8429082f6c
# Gist: https://gist.github.com/anonymuse/502e7bf5c7b67bb95a4250cdccbc5125

# Set global environment variables
workers=${WORKERS:-"node01 node02 node03 node04"}
master=master01
swarm_port=2377

# Creates a local Docker Machine VM
# Arguments:
#   $1: the name of the Docker Machine
create_machine() {
  docker-machine create \
    -d virtualbox \
    $1
}

# Function to save configuration loading while we switch Docker Machine
# environment variables
# Arguments:
#   $@: the Docker engine commmand that we'll load into the configuration
swarm_master() {
  docker $master_conf $@
}

# The body of our script
main() {
#
  if [ -z "$WORKERS" ]; then
    echo "Using default $workers. Set \$WORKERS environment variable to alter."
  fi

  # Create your master node
  echo "Creating master node"
  create_machine $master

  # Derive useful variables for Swarm setup
  master_ip=$(docker-machine ip ${master})
  master_conf=$(docker-machine config ${master})

  # Initialize the swarm mode
  echo "Initializing the swarm mode"
  swarm_master swarm init --advertise-addr $master_ip

  # Obtain the worker token
  worker_token=$(docker ${master_conf} swarm join-token -q worker)
  echo "Worker token: ${worker_token}"

  # Create and join the workers
  for worker in $workers; do
    echo "Creating worker ${worker}"
    create_machine $worker &
  done
  wait
  for worker in $workers; do
    worker_conf=$(docker-machine config ${worker})
    echo "Node $worker information:"
    docker $worker_conf swarm join --token $worker_token $master_ip:$swarm_port
  done

# Dsplay the cluster info
echo "====================="
echo "Cluster information"
echo "Discovery token: ${worker_token}"
echo "====================="
echo "Swarm manager setup:"
docker-machine env $master
echo "====================="
echo "Docker Machine cluster status"
docker-machine ls
echo "====================="
echo "Docker Swarm node status"
swarm_master node ls

}
main $@

