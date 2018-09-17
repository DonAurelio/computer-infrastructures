#!/bin/bash

# Script settings
MPI_USER='mpiuser'

# Create and MPI user on the Master
function create_mpi_user(){
  echo "Creating the MPI user $MPI_USER"

  # Adding an MPI user to run MPI jobs
  adduser --disabled-password --gecos "" $MPI_USER
  echo "$MPI_USER:$MPI_USER" | chpasswd
  # make mpiuser sudoer
  usermod -aG sudo $MPI_USER
  # Checking if user was added succesfully
  if [ $? -eq 0 ]
  then
    echo "User $MPI_USER created succesfully"
  else
    echo "User $MPI_USER could not be created" >&2
  fi
}

# Add a Slave in the /etc/hosts file
function add_host(){
  echo "Adding a new host to /etc/hosts"

  local host_address=${1}

  host_number = "$(grep slave_ /etc/hosts | wc -l)"
  output = "$(grep $host_address /etc/hosts)"

  # If the host_address does not exits in /etc/hosts
  # we add it.
  if [ -n $output ]
  then
    echo "Adding the ${host_address} IP address with host name slave_$host_number to /etc/hosts on master"
    echo -e "$host_address\tslave_$host_number" >> /etc/hosts
    echo "Host added succesfully"
  else
    echo "The hosts $host_address already exits" >&2
    echo $output
    echo "Host ${host_address} could not be added to /etc/hosts" >&2
  fi
}

# Install and start the ssh server
function setting_up_ssh(){
  echo "Setting up the ssh server"

  apt-get update -y
  # SSHPASS allor to pass the password to the ssh command
  # without user interaction
  apt-get install -y sshpass
  # Install the SSH server
  apt-get install -y openssh-server
  # Running the ssh service
  service ssh start
  # Checking if user was added succesfully
  if [ $? -eq 0 ]
  then
    echo "SSH server running"
  else
    echo "SSH could not be configured" >&2
  fi
}


# Create a private and public ssk keys
function setting_up_ssh_keys(){
  echo "Setting up private and public ssh keys"

  # Checking if the mpi ssh key already exists
  if [ -f '~/.ssh/mpi/id_rsa' ]
  then
    echo "You already have an MPI ssh key"
  else
    echo "Creating a folder ~/.ssh/mpi/ to hold MPI SSH keys"
    # Creating a folder to hold MPI SSH keys
    mkdir -p ~/.ssh/mpi/

    echo "Creating the private and public ssh keys"
    # We use su -c "command" mpiuser
    # to run the following commands from 
    # root on behalf of mpiuser 
    # Creationg the public and private keys
    su -c "ssh-keygen -t rsa -N '' -f ~/.ssh/mpi/id_rsa" ${MPI_USER}
    # Avoid checking if the remote host is reliable
    su -c "echo 'StrictHostKeyChecking=no' >> ~/.ssh/config" ${MPI_USER}
    # Sharing the public key with myself
    su -c "sshpass -p '${MPI_USER}' ssh-copy-id -i ~/.ssh/mpi/id_rsa  localhost" ${MPI_USER}

  fi
  echo "Setting up private and public ssh keys finished succesfully"
}

# Send the public ssh key to a slave node
function share_ssh_public_key(){
  local host_address=$2

  # Checking if the mpi ssh key already exists
  if [ -f '~/.ssh/mpi/id_rsa' ]
  then
    echo "Sharing the public key with $host_address"
    # Sharing the public key with the remote slave
    su -c "sshpass -p '$MPI_USER' ssh-copy-id -i ~/.ssh/mpi/id_rsa $MPI_USER@$host_address" ${MPI_USER}
  else
    echo "You dont have ssh keys to share" >&2
  fi
}

function setting_up_mpi(){
  echo "Setting up MPI"
  # Installing OpenMPI library
  apt-get update -y
  apt-get install -y make openmpi-bin openmpi-doc libopenmpi-dev
  # Checking if mpi was installed succesfully
  if [ $? -eq 0 ]
  then
    echo "MPI was installed succesfully"
  else
    echo "MPI can not be installed properly" >&2
  fi
}

function setting_up_nfs(){
  echo "Setting NFS Server"

  echo "Installing NFS Server"
  # Install the nfs server package
  apt-get install -y nfs-kernel-server

  echo "Creating NFS shared directory /home/$MPI_USER/cloud"
  # Creating the shared directory
  mkdir -p '/home/$MPI_USER/cloud'
  # Indicating the directory that will be shared
  # sed -e '/home/mpiuser/cloud *(rw,sync,no_root_squash,no_subtree_check)' -ibak /etc/exports
  echo '/home/$MPI_USER/cloud *(rw,sync,no_root_squash,no_subtree_check)' >> /etc/exports
  # Exporting shared directories
  exportfs -a
  # Restarting the NFS server
  service nfs-kernel-server restart
  if [ $? -eq 0 ]
  then
    echo "NFS server running"
  else
    echo "NFS could not be configured properly" >&2
  fi
}


# Parsing argumnets
POSITIONAL=''
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -config)
    create_mpi_user
    setting_up_ssh
    setting_up_ssh_keys
    setting_up_nfs
    setting_up_mpi
    shift # past argument
    shift # past value
    ;;
    -share_public_key)
    HOST_IP="$2"
    add_host $HOST_IP
    share_ssh_public_key $HOST_IP
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    echo "The $POSITIONAL arguments is not a valid argument"
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters
