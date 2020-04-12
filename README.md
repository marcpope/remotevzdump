# remotevzdump
Backup an OpenVZ Container(s) to a Remote Server with Minimal Downtime

This script was forked from ezvzdump by Alex Lance (alla at cyber.com.au)
https://wiki.openvz.org/Backup_a_running_container_over_the_network_with_ezvzdump

Modified to not utilize a local cache which speeds up the initial backup and subsequent backups by 50% and reduces the double storage requirement on the primary server.

Assumes:
1. you are using Port 22 for rsync to the remote server
2. you have SSH keys already installed between the host OpenVZ node and the remote backup server
3. You must run from the Main OpenVZ Node, not from inside a container.

Warning: (From Previous Developer)
DO NOT ENTER A VZ CONTAINER (vzctl enter XXX) while you are backing up, it may cause damage.

To use:
1. Modify the VEIDS to the containers you want to backup
2. Modify the Paths, if they aren't the same as your environment (it will make the /vz/remotevzdump folder automatically)
3. Modify the REMOTE_HOST and REMOTE_DIR variables for your backup server
4. Add any excludes with the RSYNC_EXCLUDE variable
5. At the bottom of the script, you can make it email you logs, if you want. (Uncomment and put in your server details)

