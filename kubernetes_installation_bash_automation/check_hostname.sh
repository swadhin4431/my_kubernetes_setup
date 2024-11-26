#!/bin/bash

### check host name


source host_details.sh


check_hostname () {
  for host in ${hosts[@]}; do
     echo "check hostname for $host";
     sshpass -p $password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ForwardX11=no  $user_name@$host 'hostname' || echo "Failed to connect to $host";
  done
}

# Check if hosts are provided as arguments
#if [ "$#" -eq 0 ]; then
#  echo "Usage: $0 <host1> <host2> ... <hostN>"
#    exit 1
#    fi


check_hostname 
