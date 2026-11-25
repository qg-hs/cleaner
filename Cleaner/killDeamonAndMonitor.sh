#!/bin/sh

#  killDeamonAndMonitor.sh
#  Cleaner
#
#  
#  Copyright © 2018 Tencent. All rights reserved.
launchctl unload /Library/LaunchDaemons/com.cleaner.daemon.plist
launchctl unload /Library/LaunchAgents/com.cleaner.monitor.plist
pkill -f Cleaner\ Menu\ bar
pkill -f CleanerDaemon
