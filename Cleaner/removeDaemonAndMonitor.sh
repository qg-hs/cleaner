#!/bin/sh

#  removeDaemonAndMonitor.sh
#  Cleaner
#
#  
#  Copyright © 2018 Tencent. All rights reserved.
#!/bin/sh

#  uninstall.sh
#  CleanerInstaller
#
#  
#  Copyright © 2018年 Tencent. All rights reserved.
launchctl unload /Library/LaunchDaemons/com.cleaner.daemon.plist
launchctl unload /Library/LaunchDaemons/com.cleaner.uninstall.plist
launchctl unload /Library/LaunchDaemons/com.cleaner.trash.plist
launchctl unload /Library/LaunchAgents/com.cleaner.monitor.plist

launchctl unload ~/Library/LaunchAgents/com.cleaner.trash.plist
launchctl unload ~/Library/LaunchAgents/com.cleaner.monitor.trash.plist




rm -rf /Library/Application\ Support/Cleaner
rm -f /Library/LaunchDaemons/com.cleaner.daemon.plist
rm -f /Library/LaunchDaemons/com.cleaner.uninstall.plist
rm -f /Library/LaunchAgents/com.cleaner.monitor.plist
rm -f /Library/LaunchDaemons/com.cleaner.trash.plist

rm -f ~/Library/LaunchAgents/com.cleaner.trash.plist
rm -f ~/Library/LaunchAgents/com.cleaner.monitor.trash.plist

# 要先删掉文件再kill, unload后立马kill,系统可能还会立马把CleanerDaemon重新拉起
# 先把文件删了，系统想拉起也找不到文件了。

pkill -f Cleaner\ uninstall-monitor
pkill -f CleanerDaemon
pkill -f CleanerUpdate
