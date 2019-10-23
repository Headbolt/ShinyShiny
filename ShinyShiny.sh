#!/bin/bash
#
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
#   This Script is designed for use in JAMF
#
#   This script will either Upgrade or Clean Install the Specified MacOS Version from local Source
#
####################################################################################################
#
# HISTORY
#
#   Version: 1.1 - 21/10/2019
#
#   - 17/01/2019 - V1.0 - Created by Headbolt
#
#   - 21/10/2019 - V1.1 - Updated by Headbolt
#                           More comprehensive error checking and notation
#
####################################################################################################
#
#   DEFINE VARIABLES & READ IN PARAMETERS
#
####################################################################################################
#
# Grab path to OS installer from JAMF variable #6 eg. /Applications/Install macOS High Sierra.app
OSInstaller="$4"
#
# Grab Erase and Install Choice from JAMF variable #5 eg. 1
# Options: 0 = Disabled / 1 = Enabled [Erase & Install macOS (Factory Defaults) is Default choice]
# This Option requires macOS Installer 10.13.4 or later
#
eraseInstall="$5"
if [[ "${eraseInstall:=0}" != 1 ]]
	then 
		eraseInstall=0
fi
#
validChecksum=0
#
# Set the name of the script for later logging
ScriptName="append prefix here as needed - Upgrade Operating System"
#
###############################################################################################################################################
#
# SCRIPT CONTENTS - DO NOT MODIFY BELOW THIS LINE
#
###############################################################################################################################################
#
# Defining Functions
#
###############################################################################################################################################
#
# CLEAN EXIT
#
cleanExit() {
	/bin/kill "${caffeinatePID}"
	exit "$1"
}
#
###############################################################################################################################################
#
# PREFLIGHT CHECKS
#
preflightchecks() {
#
/bin/echo "Running PreFlight Checks"
# Outputting a Blank Line for Reporting Purposes
/bin/echo  
#
##Caffeinate
/usr/bin/caffeinate -dis &
caffeinatePID=$!
#
osMajor=$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $2}' )
osMinor=$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $3}' )
#
##Check for existing OS installer
#
if [ -e "$OSInstaller" ]
	then
		/bin/echo "$OSInstaller found."
		# Outputting a Blank Line for Reporting Purposes
		/bin/echo
		#
		if [ -f "$OSInstaller/Contents/SharedSupport/InstallInfo.plist" ]
			then
				/bin/echo "File $OSInstaller/Contents/SharedSupport/InstallInfo.plist does exist."
				OSVersion=$(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$OSInstaller/Contents/SharedSupport/InstallInfo.plist")
			else
				/bin/echo "File $OSInstaller/Contents/SharedSupport/InstallInfo.plist does NOT exist."
				/bin/echo "Trying $OSInstaller/Contents/version.plist"
				#
				if [ -f "$OSInstaller/Contents/version.plist" ]
					then
						/bin/echo "File $OSInstaller/version.plist does exist."
						OSV=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$OSInstaller/Contents/version.plist")
						OSVersion=$( /bin/echo 10.$OSV )
						#
					else
						/bin/echo "File $OSInstaller/Contents/version.plist does NOT exist."
				fi
		fi
		# Outputting a Blank Line for Reporting Purposes
		/bin/echo
		#
	else
		/bin/echo "$OSInstaller NOT found."
		ScriptEnd
		cleanExit 1
fi
#
versionMajor=$( /bin/echo "$OSVersion" | /usr/bin/awk -F. '{print $2}' )
versionMinor=$( /bin/echo "$OSVersion" | /usr/bin/awk -F. '{print $3}' )
#
if [[ ${osMajor} == ${versionMajor} ]]
	then
		if [[ $eraseInstall == 0 ]]
			then
				/bin/echo "macOS Major Version To Be Installed is 10.$versionMajor and Current Installed Version is 10.$osMajor"
				/bin/echo "Nothing To Do"
				ScriptEnd
				cleanExit 1
			else
				/bin/echo "macOS Version To Be Installed is $OSVersion"
		fi
	else
		/bin/echo "macOS Version To Be Installed is $OSVersion"
fi
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
##Get Current User
currentUser=$( /usr/bin/stat -f %Su /dev/console )
/bin/echo "Current User is ${currentUser}"
#
##Check if FileVault Enabled
fvStatus=$( /usr/bin/fdesetup status | head -1 )
/bin/echo "FileVault Status = ${fvStatus}"
#
##Check if device is on battery or ac power
pwrAdapter=$( /usr/bin/pmset -g ps )
if [[ ${pwrAdapter} == *"AC Power"* ]]; then
	pwrStatus="OK"
	/bin/echo "Power Check: OK - AC Power Detected"
else
	pwrStatus="ERROR"
	/bin/echo "Power Check: ERROR - No AC Power Detected"
fi
#
##Check if free space > 15GB
#
if [[ $osMajor -eq 12 ]] || [[ $osMajor -eq 13 && $osMinor -lt 4 ]]; then
	freeSpace=$( /usr/sbin/diskutil info / | /usr/bin/grep "Available Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- )
else
	freeSpace=$( /usr/sbin/diskutil info / | /usr/bin/grep "Free Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- )
fi
#
if [[ ${freeSpace%.*} -ge 15000000000 ]]; then
	spaceStatus="OK"
	/bin/echo "Disk Check: OK - ${freeSpace%.*} Bytes Free Space Detected"
else
	spaceStatus="ERROR"
	/bin/echo "Disk Check: ERROR - ${freeSpace%.*} Bytes Free Space Detected"
fi
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo  
#
}
#
###############################################################################################################################################
#
# CREATE FIRST BOOT SCRIPT
#
firstbootscript() {
#
/bin/mkdir -p /usr/local/jamfps
#
/bin/echo "Creating First Run Script to remove the installer"
# Outputting a Blank Line for Reporting Purposes
/bin/echo    
#
#
/bin/echo "#!/bin/bash
## First Run Script to remove the installer.
## Clean up files
/bin/rm -fr \"$OSInstaller\"
/bin/sleep 2
## Update Device Inventory
/usr/local/jamf/bin/jamf recon
## Remove LaunchDaemon
/bin/rm -f /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
## Remove Script
/bin/rm -fr /usr/local/jamfps
exit 0" > /usr/local/jamfps/finishOSInstall.sh
#
/usr/sbin/chown root:admin /usr/local/jamfps/finishOSInstall.sh
/bin/chmod 755 /usr/local/jamfps/finishOSInstall.sh
#
}
#
###############################################################################################################################################
#
# CREATE LAUNCH DAEMON
#
launchdaemon() {
#
/bin/echo "Creating Launch Daemon"
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
/bin/cat << EOF > /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jamfps.cleanupOSInstall</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>/usr/local/jamfps/finishOSInstall.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
#
##Set the permission on the file just made.
/usr/sbin/chown root:wheel /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
/bin/chmod 644 /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
#
}
#
###############################################################################################################################################
#
# CREATE LAUNCH AGENT
#
launchagent() {
#
/bin/echo "Creating Launch Agent"
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
##Determine Program Argument
if [[ $osMajor -ge 11 ]]; then
	progArgument="osinstallersetupd"
elif [[ $osMajor -eq 10 ]]; then
	progArgument="osinstallersetupplaind"
fi
#
/bin/cat << EOP > /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.apple.install.osinstallersetupd</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>MachServices</key>
    <dict>
        <key>com.apple.install.osinstallersetupd</key>
        <true/>
    </dict>
    <key>TimeOut</key>
    <integer>300</integer>
    <key>OnDemand</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
        <string>$OSInstaller/Contents/Frameworks/OSInstallerSetup.framework/Resources/$progArgument</string>
    </array>
</dict>
</plist>
EOP
#
##Set the permission on the file just made.
/usr/sbin/chown root:wheel /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
/bin/chmod 644 /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
#
}
#
###############################################################################################################################################
#
# RUN UPGRADE
#
processupgrade() {
#
#macOS Installer 10.13.3 or ealier set 0 to it.
if [ "$versionMajor${versionMinor:=0}" -lt 134 ]
	then
		/bin/echo "Script is configured for Erase and Install of macOS."
		/bin/echo "However this is only Supported on macOS 10.13.3 and above."
		/bin/echo "Reconfiguring to Upgrade only."
		/bin/echo
		eraseInstall=0
fi
#
if [[ ${pwrStatus} == "OK" ]] && [[ ${spaceStatus} == "OK" ]]
	then
		/bin/echo "Launching jamfHelper"
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper &
		jamfHelperPID=$!
		#
		if [[ ${fvStatus} == "FileVault is On." ]] && [[ ${currentUser} != "root" ]]
			then
				# Outputting a Blank Line for Reporting Purposes
				/bin/echo
				/bin/echo "FileVault is On. Launching Agent to deal with FileVault Authenticated Reboots"
				#
				userID=$( /usr/bin/id -u "${currentUser}" )
				/bin/launchctl bootstrap gui/"${userID}" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
		fi
		#
		# Outputting a Blank Line for Reporting Purposes
		/bin/echo
        /bin/echo "Launching startosinstall..."
		#
		if [[ $eraseInstall == 1 ]]
			then
				eraseopt='--eraseinstall'
				# Outputting a Blank Line for Reporting Purposes
				/bin/echo
				/bin/echo "Script is configured for Erase and Install of macOS."
		fi
		#
		osinstallLogfile="/var/log/startosinstall.log"
		#
		if [ "$versionMajor" -ge 14 ]
			then
				eval /usr/bin/nohup "\"$OSInstaller/Contents/Resources/startosinstall\"" "$eraseopt" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$osinstallLogfile" &
			else
				eval /usr/bin/nohup "\"$OSInstaller/Contents/Resources/startosinstall\"" "$eraseopt" --applicationpath "\"$OSInstaller\"" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$osinstallLogfile" &
		fi
		#
		/bin/sleep 3
	else
		/bin/rm -f /usr/local/jamfps/finishOSInstall.sh
		/bin/rm -f /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
		/bin/rm -f /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
		/bin/echo "Launching jamfHelper Dialog (Requirements Not Met)..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$icon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure you are connected to power and that you have at least 15GB of Free Space.
		If you continue to experience this issue, please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1
fi
#
}
#
###############################################################################################################################################
#
# Section End Function
#
SectionEnd(){
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
# Outputting a Dotted Line for Reporting Purposes
/bin/echo  -----------------------------------------------
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
}
#
###############################################################################################################################################
#
# Script End Function
#
ScriptEnd(){
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
/bin/echo Ending Script '"'$ScriptName'"'
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
# Outputting a Dotted Line for Reporting Purposes
/bin/echo  -----------------------------------------------
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
#
}
#
###############################################################################################################################################
#
# End Of Function Definition
#
###############################################################################################################################################
#
# Beginning Processing
#
###############################################################################################################################################
#
# Outputting a Blank Line for Reporting Purposes
/bin/echo
SectionEnd
#
preflightchecks
SectionEnd
#
firstbootscript
SectionEnd
#
launchdaemon
SectionEnd
#
launchagent
SectionEnd
#
processupgrade
SectionEnd
ScriptEnd
#
cleanExit 0
