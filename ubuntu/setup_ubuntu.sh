#!/bin/bash

# Ubuntu Server Configuration -- a basic script to automate some common configuration tasks

##### Global Variables #####

sudo="sudo"
output_file="output.log"
packages="auditd audispd-plugins rsyslog openssh-server whois git htop hping3 net-tools curl nmap ndiff vim git ntp tshark apt-transport-https ca-certificates software-properties-common fail2ban jq"
AUDIT_RULE_URL="https://raw.githubusercontent.com/Hacks4Snacks/linux-auditd/master/audit.rules"

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

# OS verification
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
else
    echo "Can not identify OS"
    exit 1
fi

if [[ "${NAME}" != "Ubuntu" ]]; then
    echo "Only Ubuntu is supported at this time."
    exit 1
fi

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
install_packages() {
    $sudo apt update
    $sudo apt upgrade -y
    $sudo apt install -y ${packages["${release}"]}
    return 0
}

# Modify the sshd_config file
# shellcheck disable=2116
change_ssh_config() {
    $sudo sed -re 's/^(\#?)(PasswordAuthentication)([[:space:]]+)yes/\2\3no/' -i."$(echo 'old')" /etc/ssh/sshd_config
    $sudo sed -re 's/^(\#?)(PermitRootLogin)([[:space:]]+)(.*)/PermitRootLogin no/' -i /etc/ssh/sshd_config
}

# Harden network options with sysctl
sysctl_harden() {
    # IP Spoofing protection
    echo "net.ipv4.conf.all.rp_filter = 1" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.conf.default.rp_filter = 1" | $sudo tee -a /etc/sysctl.conf
    # Disable source packet routing
    echo "net.ipv4.conf.all.accept_source_route = 0" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv6.conf.all.accept_source_route = 0" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.conf.default.accept_source_route = 0" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv6.conf.default.accept_source_route = 0" | $sudo tee -a /etc/sysctl.conf
    # Ignore send redirects
    echo "net.ipv4.conf.all.send_redirects = 0" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.conf.default.send_redirects = 0" | $sudo tee -a /etc/sysctl.conf
    # Block SYN attacks
    echo "net.ipv4.tcp_syncookies = 1" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_max_syn_backlog = 2048" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_synack_retries = 2" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_syn_retries = 5" | $sudo tee -a /etc/sysctl.conf
    # Log Martians
    echo "net.ipv4.conf.all.log_martians = 1" | $sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.icmp_ignore_bogus_error_responses = 1" | $sudo tee -a /etc/sysctl.conf
    # Ignore ICMP redirects
    #	echo "net.ipv4.conf.all.accept_redirects = 0" | $sudo tee -a /etc/sysctl.conf
    #	echo "net.ipv6.conf.all.accept_redirects = 0" | $sudo tee -a /etc/sysctl.conf
    #	echo "net.ipv4.conf.default.accept_redirects = 0" | $sudo tee -a /etc/sysctl.conf
    #	echo "net.ipv6.conf.default.accept_redirects = 0" | $sudo tee -a /etc/sysctl.conf

    # Ignore Directed pings
    #	echo "net.ipv4.icmp_echo_ignore_all = 1" | $sudo tee -a /etc/sysctl.conf
    $sudo sysctl -p
}

# Setup the Uncomplicated Firewall
setup_ufw() {
    $sudo ufw allow OpenSSH
    yes y | sudo ufw enable
}

# Remove snapd artifacts from the host
snapd_remove() {
    for i in $(snap list | grep -vE 'Name' | awk '{print $1}'); do $sudo snap remove "$i"; done
    $sudo systemctl stop snapd
    $sudo umount -lf /snap/core/*
    $sudo snap remove core
    $sudo snap remove snapd
    $sudo apt purge snapd
    rm -rf ~/snap
    $sudo rm -vrf /snap /var/snap /var/lib/snapd /var/cache/snapd
    $sudo apt-mark hold snapd
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
    # Assumes Ubuntu 20.04
    $sudo systemctl restart systemd-timesyncd
}

# Gets the amount of physical memory in GB (rounded up) installed on the machine
get_physical_memory() {
    local phymem
    phymem="$(free -g | awk '/^Mem:/{print $2}')"

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

# Configure Auditd
configure_auditd() {
    $sudo wget -q -O /tmp/audit.rules ${AUDIT_RULE_URL}
    $sudo cp /tmp/audit.rules /etc/audit/rules.d/
    $sudo sed -i 's/active = no/active = yes/' /etc/audisp/plugins.d/syslog.conf
    $sudo sed -i 's/args = LOG_INFO/args = LOG_LOCAL6/' /etc/audisp/plugins.d/syslog.conf
}

# Call auditd configuration and enable auditd
enable_auditd() {
    configure_auditd
    $sudo systemctl enable auditd
    $sudo systemctl start auditd
}

configure_rsyslog() {
    echo -n "Forward logs to a syslog server (y/n)?: "
    read -r syslog_forward
    if [ "$syslog_forward" = "${syslog_forward#[Yy]}" ]; then
        read -rp "Please enter syslog server IP (Assumes port 514/UDP ): " syslog_ip
        ${sudo} echo "*.*   @${syslog_ip}:514" | sudo tee -a /etc/rsyslog.d/50-default.conf >/dev/null
    else
        :
    fi
}

# Call rsyslog configuration function and enable rsyslog
enable_rsyslog() {
    configure_rsyslog
    $sudo systemctl enable rsyslog
    $sudo systemctl start rsyslog
}

# Disables the sudo password prompt for sudo user group
disable_sudo_password() {

    $sudo cp /etc/sudoers /etc/sudoers.bak
    $sudo bash -c "echo '%sudo ALL=(ALL) NOPASSWD: ALL' | (EDITOR='tee -a' visudo)"
}

#### START OF CALLS TO FUNCTION ####

# Create main function
main() {
    print_banner
    #    read -rp "Enter the username of the new user account:" username
    echo "This script is still in development, please ensure you have SSH keys copied to the target server prior to running."
    #    prompt_password
    # Run configuration functions
    trap EXIT SIGHUP SIGINT SIGTERM

    #    add_user_account "${username}" "${password}"
    echo "Password SSH Authentication will be disabled"
    #    read -rp $'Paste in the public SSH key for current user:\n' ssh_key
    output_log "${output_file}"

    echo "Script is running."
    install_packages
    exec 3>&1 >>"${output_file}" 2>&1
    disable_sudo_password
    #    add_ssh_key "${username}" "${ssh_key}"
    configure_fail2ban
    enable_auditd
    enable_rsyslog
    change_ssh_config
    setup_ufw
    sysctl_harden
    snapd_remove

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
