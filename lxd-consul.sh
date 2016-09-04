#!/usr/bin/env bash

consul_version='0.6.4'


# container names
# container names
#filename=$2
while read line
do
    names+=("$line")
done < mp_containers.txt

command_exists () {
  type "$1" &> /dev/null ;
}

get_consul_ip(){
	lxc info "$1" | grep 'eth0:\sinet\s' | awk 'NR == 1 { print $3 }'
}

check_agent(){
  lxc exec "$1" -- ps -ef | grep 'consul\sagent' > /dev/null 2>&1
}


start(){
	echo 'starting consul containers...'
  for name in "${names[@]}";
    do
    lxc start $name
    lxc exec $name reboot
  done

}

stop(){
	echo 'stopping consul containers...'
  for name in "${names[@]}";
    do
    lxc stop $name
  done
}

restart(){
	echo 'restarting consul containers...'
	stop
	start
}

destroy(){
	echo 'destroying lxd-consul cluster...'
	# stopping cluster
  stop
	# delete containers
	echo 'deleting consul containers...'
  for name in "${names[@]}";
  do
	lxc delete -f $name
  done
	echo 'lxd-consul destroyed!'
}


create() {
  # check if lxc client is installed. if not exit out and tell to install
  if command_exists lxc; then
  	echo 'lxc client appears to be there. Proceeding with cluster creation...'
  	sleep 1
  else
  	echo 'lxd does not appear to be installed properly. Follow instructions here: https://linuxcontainers.org/lxd/getting-started-cli'
    exit 1
  fi
  
  # launch alpine container, install go, and install consul
  for name in "${names[@]}";
    do
      # create containers
      #lxc launch images:alpine/$alpine_version/amd64 "$name" -c 'environment.GOPATH=/go' -c 'security.privileged=true'
      lxc launch ubuntu:14.04 "$name" 
      # make consul dirs
      lxc exec "$name" -- sh -c "mkdir -p /consul/data /consul/server "
  done

  lxc exec "${names[0]}" -- sh -c "echo http://dl-6.alpinelinux.org/alpine/v3.4/main > /tmp/repositories && \

apt-get install unzip && \
apt-get install libjson-perl -y && \
apt-get install libwww-perl -y && \
  wget https://releases.hashicorp.com/consul/$consul_version/consul_\"$consul_version\"_linux_amd64.zip -O consul_$consul_version.zip && \
  unzip -o consul_$consul_version.zip -d /usr/bin && \
  rm -f consul_$consul_version.zip && \
  chmod 755 /usr/bin/consul && \
  mkdir -p /consul/bootstrap"


  lxc file pull "${names[0]}"/usr/bin/consul .
  for name in "${names[@]}";
    do
  lxc file push --mode=0755 query_haproxy $name/usr/bin/query_haproxy
  lxc file push --mode=0755 consul $name/usr/bin/consul
  done

  rm -f consul
leader_ip=$(get_consul_ip "${names[0]}")
sed  s/leader_ip/"$leader_ip"/g server.json > server1.json
  
  # push server config files and init script to server nodes
  for name in "${names[@]}";
    do
    lxc file push server1.json $name/consul/server/
    lxc file push consul-server-start $name/etc/init.d/
    lxc exec $name -- chmod 755 /etc/init.d/consul-server-start
    lxc exec $name update-rc.d consul-server-start  defaults 97 0
    lxc exec $name service consul-server-start
    lxc exec $name -- apt-get install libwww-perl -y
    lxc exec $name -- apt-get install libjson-perl -y
    lxc exec $name reboot
  done
  
  #start server nodes
  
  # cleanup
  rm -f *_consul*


}

case "$1" in
	create)
      create
      ;;
    destroy)
      destroy
      ;;
    start)
      start
      ;;
    stop)
      stop
      ;;
    restart)
      restart
      ;;
    *) 
      echo "Usage: $0 command {options:create,destroy,start,stop,restart}"
      exit 1
esac
