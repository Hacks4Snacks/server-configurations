#!/bin/bash

# Ubuntu Server Configuration -- a basic script to automate some common configuration tasks

##### Global Variables #####

sudo="sudo"
#release=$(lsb_release -sc)
#custom_packages=""
output_file="output.log"
packages="auditd audispd-plugins rsyslog openssh-server whois htop hping3 net-tools curl nmap ndiff vim git ntp tshark apt-transport-https ca-certificates software-properties-common fail2ban"

declare -a packages

print_banner() {
cat <<EOF
┌─────────────────────────────────────────────────────────┐
│             Ubuntu Server Configuration 0.1             │
└─────────────────────────────────────────────────────────┘
EOF
}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# TODO Check OS
#if [ -r /etc/os-release ]; then
#	next
#elif [ -f /etc/os-release ]; then
#	NAME=$(sed -rn 's/(\w+).*/\1/p')
#	VERSION_ID=$(grep -o '[0-9]\.[0-9]')
#	if [[ "${NAME}" == "Ubuntu"  ]]; then
#		UBUNTU=true
#	        if [[ "${VERSION_ID}" == "20.04" ]]; then
 #       	    UBUNTU_20=true
#	        elif [[ "${VERSION_ID}" == "18.04" ]]; then
#		        UBUNTU_18=true
#   	else
#	    	echo "Unsupported Ubuntu Version"
#	    	echo "${NAME}"
#	    	echo "${VERSION_ID}"
#	    	exit 1
#	    	fi
#else
#	echo "Unsupported Ubuntu Version"
#	echo "${NAME}"
#	echo "${VERSION_ID}"
#	exit 1
#	fi
#fi

#### START OF FUNCTIONS ####

# Create an output log of changes
output_log() {
    local filename=${1}
    {
        echo "==================="
        echo "Log generated on $(date)"
        echo "==================="
    } >>"${filename}" 2>&1
}

# TODO Add SSH key for current user
# Add the local machine public SSH Key for the new user account
# Arguments:
#   Account Username
#   Public SSH Key
#add_ssh_key() {
#    local ssh_key=${1}
#    $user -H bash -c "mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys"
#    $user -H bash -c "echo \"${sshKey}\" | sudo tee -a ~/.ssh/authorized_keys"
#    $user -H bash -c "chmod 600 ~/.ssh/authorized_keys"

#}

# Create the swap file based on amount of physical memory on machine (Maximum size of swap is 4GB)
create_swap() {
   local swapmem=$(($(getPhysicalMemory) * 2))

   # Anything over 4GB in swap is probably unnecessary as a RAM fallback
   if [ ${swapmem} -gt 4 ]; then
        swapmem=4
   fi

   $sudo fallocate -l "${swapmem}G" /swapfile
   $sudo chmod 600 /swapfile
   $sudo mkswap /swapfile
   $sudo swapon /swapfile
}

# Check for additional updates and install packages
install_packages(){
   $sudo apt update
   $sudo apt upgrade -y
   $sudo apt install -y ${packages["${release}"]}
#   $sudo apt install -y $custom_packages
   return 0
}

# Modify the sshd_config file
# shellcheck disable=2116
change_ssh_config() {
    $sudo sed -re 's/^(\#?)(PasswordAuthentication)([[:space:]]+)yes/\2\3no/' -i."$(echo 'old')" /etc/ssh/sshd_config
    $sudo sed -re 's/^(\#?)(PermitRootLogin)([[:space:]]+)(.*)/PermitRootLogin no/' -i /etc/ssh/sshd_config
}

# Setup the Uncomplicated Firewall
setup_ufw() {
    $sudo ufw allow OpenSSH
    yes y | sudo ufw enable
}

# Mount swap file
mount_swap() {
    $sudo cp /etc/fstab /etc/fstab.bak
    echo '/swapfile none swap sw 0 0' | $sudo tee -a /etc/fstab
}

# Modify the swapfile settings
# Arguments:
#   new vm.swappiness value
#   new vm.vfs_cache_pressure value
tweak_swap_settings() {
    local swappiness=${1}
    local vfs_cache_pressure=${2}

    $sudo sysctl vm.swappiness="${swappiness}"
    $sudo sysctl vm.vfs_cache_pressure="${vfs_cache_pressure}"
}

# Save the modified swap settings
# Arguments:
#   new vm.swappiness value
#   new vm.vfs_cache_pressure value
save_swap_settings() {
    local swappiness=${1}
    local vfs_cache_pressure=${2}

    echo "vm.swappiness=${swappiness}" | $sudo tee -a /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=${vfs_cache_pressure}" | $sudo tee -a /etc/sysctl.conf
}

# Set the machine's timezone
# Arguments:
#   tz data timezone
set_timezone() {
    local timezone=${1}
    echo "${1}" | $sudo tee /etc/timezone
    $sudo ln -fs "/usr/share/zoneinfo/${timezone}" /etc/localtime
    $sudo dpkg-reconfigure -f noninteractive tzdata
}

# Configure Network Time Protocol
configure_ntp() {

    $sudo systemctl restart systemd-timesyncd
}

# Gets the amount of physical memory in GB (rounded up) installed on the machine
get_physical_memory() {
    local phymem
        phymem="$(free -g|awk '/^Mem:/{print $2}')"

    if [[ ${phymem} == '0' ]]; then
        echo 1
    else
        echo "${phymem}"
    fi
}

# Enable fail2basn
configure_fail2ban() {
	$sudo systemctl enable fail2ban
	$sudo systemctl start fail2ban
}

# Enable Auditd
configure_auditd() {
        $sudo systemctl enable auditd
        $sudo systemctl start auditd
}

# TODO disable SUDO password prompt for user/group
# Disables the sudo password prompt for a user account by editing /etc/sudoers
# Arguments:
#   Account username
#disable_sudo_password() {
#    local username="${1}"

#    $sudo cp /etc/sudoers /etc/sudoers.bak
#    $sudo bash -c "echo '${1} ALL=(ALL) NOPASSWD: ALL' | (EDITOR='tee -a' visudo)"
#}


#### START OF CALLS TO FUNCTION ####

# Create main function
main() {

    print_banner
	#    read -rp "Enter the username of the new user account:" username
    echo "This script is still in development, please ensure you have SSH keys copied to the target server prior to running."
#    prompt_password
    # Run configuration functions
    trap EXIT SIGHUP SIGINT SIGTERM

#    addUserAccount "${username}" "${password}"
    echo "Password SSH Authentication will be disabled"
#    read -rp $'Paste in the public SSH key for current user:\n' ssh_key
    output_log "${output_file}"

    echo "Script is running."
    install_packages
    exec 3>&1 >>"${output_file}" 2>&1
#    disable_sudo_password "${username}"
#    add_ssh_key "${username}" "${ssh_key}"
    configure_fail2ban
    configure_auditd
    change_ssh_config
    setup_ufw


    if ! has_swap; then
        setup_swap
    fi

    setup_timezone
    configure_ntp

    $sudo service ssh restart

    echo "Configuration is complete. Log file is located at ${output_file}" >&3
}

setup_swap() {
    create_swap
    mount_swap
    tweak_swap_settings "10" "50"
    save_swap_settings "10" "50"
}

has_swap() {
    [[ "$(sudo swapon -s)" == *"/swapfile"* ]]
}


setup_timezone() {
    echo -ne "Enter the timezone for the server (Default is 'UTC'):\n" >&3
    read -r timezone
    if [ -z "${timezone}" ]; then
        timezone="UTC"
    fi
    set_timezone "${timezone}"
    echo "Timezone is set to $(cat /etc/timezone)" >&3
}

# Call main function
main
