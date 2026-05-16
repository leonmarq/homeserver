
# configure to work with debian GUI install
Install and enable SSH at boot
	sudo apt update
	sudo apt install -y openssh-server
	sudo systemctl enable --now ssh
	sudo systemctl status ssh --no-pager
Prevent sleep/suspend/hibernate entirely
	sudo mkdir -p /etc/systemd/logind.conf.d
	cat <<'EOF' | sudo tee /etc/systemd/logind.conf.d/00-nosleep.conf
	[Login]
	HandleLidSwitch=ignore
	HandleLidSwitchExternalPower=ignore
	HandleLidSwitchDocked=ignore
	IdleAction=ignore
	EOF

	sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
	sudo systemctl restart systemd-logind

Disable GUI lock/screen blanking (if desktop session runs)
	gsettings set org.gnome.desktop.session idle-delay 0
	gsettings set org.gnome.desktop.screensaver lock-enabled false
	gsettings set org.gnome.desktop.screensaver idle-activation-enabled false

# set crontabs

# configure external storage
sudo docker exec -u www-data -it nextcloud-aio-nextcloud \
php occ files_external:create /NAS smb password::password \
  -c host="192.168.2.254" \
  -c share="NAS_Public" \
  -c user="admin" \
  -c password=PASSWORD_NAS
  
sudo docker exec -u www-data -it nextcloud-aio-nextcloud php occ files_external:verify <id>



# automount
- 2 files necessary:
1. 'sudo nano /etc/systemd/system/<mnt-mountpoint>.mount'
'''
[Unit]
Description=Mount sdb1>

[Mount]
What=/dev/disk/by-uuid/<UUID_here>
Where=/mnt/<mountpoint>
Type=auto
Options=defaults

[Install]
WantedBy=multi-user.target
'''
2. 'sudo nano /etc/systemd/system/<mnt-mountpoint>.automount'
'''
[Unit]
Description=Automount usb

[Automount]
Where=/mnt/mountpoint

[Install]
WantedBy=multi-user.target


'''
<mount_id>

