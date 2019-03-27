#!/bin/bash

# erase-install
# by Graham Pugh.
#
# WARNING. This is a self-destruct script. Do not try it out on your own device!
#
# This script downloads and runs installinstallmacos.py from Greg Neagle,
# which expects you to choose a value corresponding to the version of macOS you wish to download.
# This script automatically fills in that value so that it can be run remotely.
#
# See README.md for details on use.
#
## or just run without an argument to check and download the installer as required and then run it to wipe the drive
#
# Version History
# Version 1.0     29.03.2018      Initial version. Expects a manual choice of installer from installinstallmacos.py
# Version 2.0     09.07.2018      Automatically selects a non-beta installer
# Version 3.0     03.09.2018      Changed and additional options for selecting non-standard builds. See README
# Version 3.1     17.09.2018      Added ability to specify a build in the parameters, and we now clear out the cached content
# Version 3.2     21.09.2018      Added ability to specify a macOS version. And fixed the --overwrite flag.
# Version 3.3     13.12.2018      Bug fix for --build option, and for exiting gracefully when nothing is downloaded.

# Version 3.4      25.03.2019     fix version checking
# Version 3.5      26.03.2019     add extra installs directory and checking. Allowing for the --installpackage option to be used automatically 

# Requirements:
# macOS 10.13.4+ is already installed on the device (for eraseinstall option)
# Device file system is APFS
#
# NOTE: at present this script downloads a forked version of Greg's script so that it can properly automate the download process

# URL for downloading installinstallmacos.py
installinstallmacos_URL="https://raw.githubusercontent.com/grahampugh/macadmin-scripts/master/installinstallmacos.py"

# Directory in which to place the macOS installer
installer_directory="/Library/Management/erase-install"

# place any extra packages that should be installed as part of the erase-install into this folder. The script will find them and install.
# https://derflounder.wordpress.com/2017/09/26/using-the-macos-high-sierra-os-installers-startosinstall-tool-to-install-additional-packages-as-post-upgrade-tasks/
extras_directory="/Library/Management/erase-install/toinstall"

# Temporary working directory
workdir="/Library/Management/erase-install"


# Functions
show_help() {
    echo "
    [erase-install] by @GrahamRPugh

    Usage:
    [sudo] bash erase-install.sh [--samebuild] [--move] [--erase] [--build=XYZ] [--overwrite] [--version=X.Y]

    [no flags]:     Finds latest current production, non-forked version
                    of macOS, downloads it.
    --samebuild:    Finds the version of macOS that matches the
                    existing system version, downloads it.
    --version=X.Y:  Finds a specific inputted version of macOS if available
                    and downloads it if so. Will choose the lowest matching build.
    --build=XYZ:    Finds a specific inputted build of macOS if available
                    and downloads it if so.
    --move:         If not erasing, moves the
                    downloaded macOS installer to $installer_directory
    --erase:        After download, erases the current system
                    and reinstalls macOS
    --overwrite:    Download macOS installer even if an installer
                    already exists in $installer_directory

    Note: If existing installer is found, this script will not check
          to see if it matches the installed system version. It will
          only check whether it is a valid installer. If you need to
          ensure that the currently installed version of macOS is used
          to wipe the device, use the --overwrite parameter.
    "
    exit
}

############# v 3.4 
# added bash code to validate versions

versionsComparison () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

testVersionsComparison () {
    versionsComparison $1 $2
    case $? in
        0) op='='
        caseexit="0"
        versionsOK="yes"
        ;;
        1) op='>'
        caseexit="1"
        versionsOK="yes"
        ;;
        2) op='<'
        caseexit="2"
        versionsOK="no"
        ;;
        *)
        caseexit="*"
        versionsOK="no"
    esac
    echo "$caseexit:$versionsOK"
}

#############


# Version 3.5
find_extra_installers () {

# find any pkg files in the extras directory
extra_installs=$(find "$extras_directory"/*.pkg -maxdepth 1)
# set install_package_list to blank. 
install_package_list=()

# need to ignore spaces in pkg names
old_IFS=$IFS
IFS=$(echo -en "\n\b")

# loop round list and build array to inject
for pkg in $extra_installs
	do
	echo  name is $pkg
	install_package_list+=( --installpackage )
	
	if [[ $pkg = ${pkg%[[:space:]]*} ]]; then
   		install_package_list+=( "$pkg" )
	else
		# could not get packages with a space in the name to work in the install
		# so for simplicity rename the file and use the new name
		packagename_nospace=$(echo $pkg | sed 's/ /_/g')
		mv "$pkg" "$packagename_nospace"
   		install_package_list+=( "$packagename_nospace" )
	fi
	
	done
	
# reset the IFS
IFS=${old_IFS}

}

find_existing_installer() {
    installer_app=$( find "$installer_directory/"*macOS*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
    # Search for an existing download
    macOSDMG=$( find $workdir/*.dmg -maxdepth 1 -type f -print -quit 2>/dev/null )

    # First let's see if this script has been run before and left an installer
    if [[ -f "$macOSDMG" ]]; then
        echo "   [find_existing_installer] Valid installer found at $macOSDMG."
        hdiutil attach "$macOSDMG"
        installmacOSApp=$( find '/Volumes/'*macOS*/*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
    elif [[ -d "$installer_app" ]]; then
        echo "   [find_existing_installer] Installer found at $installer_app."
        # check installer validity
        # updated version gathering below v3.4
        installer_version_main=$( /usr/bin/defaults read "$installer_app/Contents/Info.plist" DTPlatformVersion | sed 's|10\.||')
		installer_subversion=$( /usr/bin/defaults read "$installer_app/Contents/Info.plist" CFBundleShortVersionString | awk -F"." '{print $2}')
	    installer_version=($installer_version_main.$installer_subversion)


        installed_version=$( /usr/bin/sw_vers | grep ProductVersion | awk '{ print $NF }' | sed 's|10\.||')
        # updated test versions v3.4
        testVersionsComparison "$installer_version" "$installed_version"
		if [ "$versionsOK" = "no" ]; then
            echo "   [find_existing_installer] 10.$installer_version < 10.$installed_version so not valid."
        else
            echo "   [find_existing_installer] 10.$installer_version >= 10.$installed_version so valid."
            installmacOSApp="$installer_app"
            app_is_in_applications_folder="yes"
        fi
    else
        echo "   [find_existing_installer] No valid installer found."
    fi
}

overwrite_existing_installer() {
    echo "   [overwrite_existing_installer] Overwrite option selected. Deleting existing version."
    existingInstaller=$( find /Volumes -maxdepth 1 -type d -name *'macOS'* -print -quit )
    if [[ -d "$existingInstaller" ]]; then
        diskutil unmount force "$existingInstaller"
    fi
    rm -f "$macOSDMG"
    rm -rf "$installer_app"
}

move_to_applications_folder() {
    if [[ $app_is_in_applications_folder == "yes" ]]; then
        echo "   [move_to_applications_folder] Valid installer already in $installer_directory folder"
        return
    fi
    echo "   [move_to_applications_folder] Moving installer to $installer_directory folder"
    cp -R "$installmacOSApp" $installer_directory/
    existingInstaller=$( find /Volumes -maxdepth 1 -type d -name *'macOS'* -print -quit )
    if [[ -d "$existingInstaller" ]]; then
        diskutil unmount force "$existingInstaller"
    fi
    rm -f "$macOSDMG"
    echo "   [move_to_applications_folder] Installer moved to $installer_directory folder"
}

run_installinstallmacos() {
    # Download installinstallmacos.py
    if [[ ! -d "$workdir" ]]; then
        echo "   [run_installinstallmacos] Making working directory at $workdir"
        mkdir -p $workdir
    fi
    echo "   [run_installinstallmacos] Downloading installinstallmacos.py to $workdir"
    curl -s $installinstallmacos_URL > "$workdir/installinstallmacos.py"

    # Use installinstallmacos.py to download the desired version of macOS
    installinstallmacos_args=''
    if [[ $prechosen_version ]]; then
        echo "   [run_installinstallmacos] Checking that selected version $prechosen_version is available"
        installinstallmacos_args+="--version=$prechosen_version"
        [[ $erase == "yes" ]] && installinstallmacos_args+=" --validate"

    elif [[ $prechosen_build ]]; then
        echo "   [run_installinstallmacos] Checking that selected build $prechosen_build is available"
        installinstallmacos_args+="--build=$prechosen_build"
        [[ $erase == "yes" ]] && installinstallmacos_args+=" --validate"

    elif [[ $samebuild == "yes" ]]; then
        echo "   [run_installinstallmacos] Checking that current build $installed_build is available"
        installinstallmacos_args+="--current"

    else
        echo "   [run_installinstallmacos] Getting current production version"
        installinstallmacos_args+="--auto"
    fi

    python "$workdir/installinstallmacos.py" --workdir=$workdir --ignore-cache --compress $installinstallmacos_args

    # Identify the installer dmg
    macOSDMG=$( find $workdir -maxdepth 1 -name 'Install_macOS*.dmg'  -print -quit )
    if [[ -f "$macOSDMG" ]]; then
        echo "   [run_installinstallmacos] Mounting disk image to identify installer app."
        hdiutil attach "$macOSDMG"
        installmacOSApp=$( find '/Volumes/'*macOS*/*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
    else
        echo "   [run_installinstallmacos] No disk image found. I guess nothing got downloaded."
        /usr/bin/pkill jamfHelper
        exit
    fi
}

# Main body

# Safety mechanism to prevent unwanted wipe while testing
erase="no"

while test $# -gt 0
do
    case "$1" in
        -e|--erase) erase="yes"
            ;;
        -m|--move) move="yes"
            ;;
        -s|--samebuild) samebuild="yes"
            ;;
        -o|--overwrite) overwrite="yes"
            ;;
        --version*)
            prechosen_version=$(echo $1 | sed -e 's/^[^=]*=//g')
            ;;
        --build*)
            prechosen_build=$(echo $1 | sed -e 's/^[^=]*=//g')
            ;;
        -h|--help) show_help
            ;;
    esac
    shift
done

echo
echo "   [erase-install] Script execution started: $(date)"

# Display full screen message if this screen is running on Jamf Pro
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Look for the installer, download it if it is not present
echo "   [erase-install] Looking for existing installer"
find_existing_installer

if [[ $overwrite == "yes" && -d "$installmacOSApp" ]]; then
    overwrite_existing_installer
fi

if [[ ! -d "$installmacOSApp" ]]; then
    echo "   [erase-install] Starting download process"
    if [[ -f "$jamfHelper" && $erase == "yes" ]]; then
        "$jamfHelper" -windowType hud -windowPosition ul -title "Downloading macOS" -alignHeading center -alignDescription left -description "We need to download the macOS installer to your computer; this will take several minutes." -lockHUD -icon  "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" -iconSize 100 &
        # jamfPID=$(echo $!)
    fi
    # now run installinstallmacos
    run_installinstallmacos
    # Once finished downloading, kill the jamfHelper
    /usr/bin/pkill jamfHelper
fi

if [[ $erase != "yes" ]]; then
    appName=$( basename "$installmacOSApp" )
    if [[ -d "$installmacOSApp" ]]; then
        echo "   [main] Installer is at: $installmacOSApp"
    fi

    # Move to $installer_directory if move_to_applications_folder flag is included
    if [[ $move == "yes" ]]; then
        move_to_applications_folder
    fi

    # Unmount the dmg
    existingInstaller=$( find /Volumes -maxdepth 1 -type d -name *'macOS'* -print -quit )
    if [[ -d "$existingInstaller" ]]; then
        diskutil unmount force "$existingInstaller"
    fi
    # Clear the working directory
    rm -rf "$workdir/content"
    echo
    exit
fi

# 5. Run the installer
echo
echo "   [main] WARNING! Running $installmacOSApp with eraseinstall option"
echo

if [[ -f "$jamfHelper" && $erase == "yes" ]]; then
    echo "   [erase-install] Opening jamfHelper full screen message"
    "$jamfHelper" -windowType fs -title "Erasing macOS" -alignHeading center -heading "Erasing macOS" -alignDescription center -description "This computer is now being erased and is locked until rebuilt" -icon "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/Lock.jpg" &
    jamfPID=$(echo $!)
fi


# version 3.5 added check for packages then add install_package_list to end of command line
# if there are none then standard command line is used
find_extra_installers

# vary command line based on installer versions
if [ "$installer_version_main" = "13" ]; then
"$installmacOSApp/Contents/Resources/startosinstall" --applicationpath "$installmacOSApp" --eraseinstall --agreetolicense --nointeraction "${install_package_list[@]}"
else
"$installmacOSApp/Contents/Resources/startosinstall" --eraseinstall --agreetolicense --nointeraction "${install_package_list[@]}"
fi
# Kill Jamf FUD if startosinstall ends before a reboot
[[ $jamfPID ]] && kill $jamfPID
