![alt text](https://infinitericks.com/wp-content/uploads/2024/10/cropped-logoricks.png)  
                
                
                
                
                           Multiverse Cryptocurrency InfiniteRicks

Type	PoS

Coin name	InfiniteRicks

Coin abbreviation	RICK

Address letter	1

Min stake age 12 Hours

Block time 2 min

APR  307% a year

RPC port	31648

P2P port	31647


Blockexplorer 
https://explorer.infinitericks.com

Official Website 
https://infinitericks.com


##How to compile and use the Linux Deamon
Tested and working on Ubuntu 16.04, 18.04, 22.04 and 24.04.

### Swapfile
You can check if your server has a swap file already with the ```swapon``` command.  If your system has less than 1.5GB of memory, you'll want at least a 2GB swap area.  Add a new swapfile with:
```
sudo fallocate -l 2G /swapfile
sudo chown root:root /swapfile
sudo chmod 0600 /swapfile
sudo bash -c "echo 'vm.swappiness = 10' >> /etc/sysctl.conf"
sudo mkswap /swapfile
sudo swapon /swapfile
```
If fallocate doesn’t work, you can instead use:
```
sudo dd if=/dev/zero of=/swapfile bs=1024 count=1024288
```
Initialize the swapfile to mount automatically on boot:
```
sudo echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### Install all required dependencies

Ubuntu 22.04 / 24.04:
```
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get -y install nano ntp unzip git build-essential libssl-dev
sudo apt-get -y install libdb-dev libdb++-dev libboost-all-dev libminiupnpc-dev
```

Ubuntu 18.04 (legacy):
```
sudo apt-get -y install nano ntp unzip git build-essential libssl1.0-dev
sudo apt-get -y install libdb-dev libdb++-dev libboost-all-dev libminiupnpc-dev
sudo apt-get install libqt4-dev
```
If you get an error mentioning lock files, you probably have a desktop or background package update tool running that prevents other apt changes from happening.  You can use the ```lsof``` utility to figure out what program holds the lock and then pause it from running.

Pull the source code from github, or download it yourself:
```
git clone https://github.com/Coindev400/InfiniteRicks.git
```

### Compiling the software

Now you compile the included leveldb:
```
chmod 777 -R InfiniteRicks
cd InfiniteRicks/src/leveldb
make clean
make libleveldb.a libmemenv.a
```
Return to the source directory, and compile the daemon and tools:
```
cd ..
make -f makefile.unix
```
This builds `InfiniteRicksd`, `InfiniteRicks-cli`, and `InfiniteRicks-tx`.
To build only one binary:
```
make -f makefile.unix InfiniteRicksd
make -f makefile.unix InfiniteRicks-cli
make -f makefile.unix InfiniteRicks-tx
```
If `make` reports `No rule to make target 'InfiniteRicks-cli'`, you are either
not in `src/` or your checkout predates the cli/tx utilities (merge PR #32).
Strip the file to make it smaller, then relocate it:
```
strip InfiniteRicksd
sudo cp InfiniteRicksd /usr/bin
```
Now run the daemon:
```
InfiniteRicksd
```
It should return an error, telling you to set up config file in a directory. 

## Create a config file

Now we’ll set up the config file. Note that this is case sensitive.
```
nano ~/.InfiniteRicks/InfiniteRicks.conf
```
Add the following, save and exit:
```
daemon=1
server=1
rpcuser=(username)
rpcpassword=(strong password)
```

Run InfiniteRicksd once more and if you did everything correctly, your daemon is now online! 
## Command summary
Type:
```
InfiniteRicksd help
```
for a full list of commands available.

InfiniteRicks development tree

InfiniteRicks is a PoS-based cryptocurrency.

## Development process
===========================

Developers work in their own trees, then submit pull requests when
they think their feature or bug fix is ready.

The patch will be accepted if there is broad consensus that it is a
good thing.  Developers should expect to rework and resubmit patches
if they don't match the project's coding conventions (see coding.txt)
or are controversial.

The master branch is regularly built and tested, but is not guaranteed
to be completely stable. Tags are regularly created to indicate new
stable release versions of InfiniteRicks.

Feature branches are created when there are major new features being
worked on by several people.

From time to time a pull request will become outdated. If this occurs, and
the pull is no longer automatically mergeable; a comment on the pull will
be used to issue a warning of closure. The pull will be closed 15 days
after the warning if action is not taken by the author. Pull requests closed
in this manner will have their corresponding issue labeled 'stagnant'.

Issues with no commits will be given a similar warning, and closed after
15 days from their last activity. Issues closed in this manner will be 
labeled 'stale'.

## InfiniteRicks-qt: Qt5 GUI for InfiniteRicks

Build instructions

Debian

First, make sure that the required packages for Qt5 development of your distribution are installed, for Debian and Ubuntu these are:
```
apt-get install qt5-default qt5-qmake qtbase5-dev-tools qttools5-dev-tools
apt-get install build-essential libboost-dev libboost-system-dev
apt-get install libboost-filesystem-dev libboost-program-options-dev libboost-thread-dev
apt-get install libssl-dev libdb++-dev
```
## This Step is needed as well
 ```
 sudo apt-get install libqt4-dev libminiupnpc-dev
```
## Then execute the following:
```
qmake RELEASE=1
make STATIC=1
```
Alternatively, install Qt Creator and open the InfiniteRicks-qt.pro file.

An executable named InfiniteRicks-qt will be built.

## Windows

## Windows build instructions:

Download the QT Windows SDK and install it. You don't need the Symbian stuff, just the desktop Qt.
Compile openssl, boost and dbcxx.
Open the .pro file in QT creator and build as normal (ctrl-B)
Mac OS X

Download and install the Qt Mac OS X SDK. It is recommended to also install Apple's Xcode with UNIX tools.
Download and install MacPorts.
Execute the following commands in a terminal to get the dependencies:
sudo port selfupdate
sudo port install boost db48 miniupnpc
Open the .pro file in Qt Creator and build as normal (cmd-B)
Build configuration options

UPNnP port forwarding

To use UPnP for port forwarding behind a NAT router (recommended, as more connections overall allow for a faster and more stable InfiniteRicks experience), pass the following argument to qmake:
```
qmake "USE_UPNP=1"
```
(in Qt Creator, you can find the setting for additional qmake arguments under "Projects" -> "Build Settings" -> "Build Steps", then click "Details" next to qmake)

This requires miniupnpc for UPnP port mapping. It can be downloaded from http://miniupnp.tuxfamily.org/files/. UPnP support is not compiled in by default.

Set USE_UPNP to a different value to control this:

USE_UPNP=-	no UPnP support, miniupnpc not required;
USE_UPNP=0	(the default) built with UPnP, support turned off by default at runtime;
USE_UPNP=1	build with UPnP support turned on by default at runtime.
Notification support for recent (k)ubuntu versions

To see desktop notifications on (k)ubuntu versions starting from 10.04, enable usage of the FreeDesktop notification interface through DBUS using the following qmake option:

qmake "USE_DBUS=1"
Generation of QR codes

libqrencode may be used to generate QRCode images for payment requests. It can be downloaded from http://fukuchi.org/works/qrencode/index.html.en, or installed via your package manager. Pass the USE_QRCODE flag to qmake to control this:

USE_QRCODE=0	(the default) No QRCode support - libarcode not required
USE_QRCODE=1	QRCode support enabled
Berkely DB version warning

A warning for people using the static binary version of InfiniteRicks on a Linux/UNIX-ish system (tl;dr: Berkely DB databases are not forward compatible).

The static binary version of InfiniteRicks is linked against libdb 5.0 (see also this Debian issue).

Now the nasty thing is that databases from 5.X are not compatible with 4.X.

If the globally installed development package of Berkely DB installed on your system is 5.X, any source you build yourself will be linked against that. The first time you run with a 5.X version the database will be upgraded, and 4.X cannot open the new format. This means that you cannot go back to the old statically linked version without significant hassle!

Ubuntu 11.10 warning

Ubuntu 11.10 has a package called 'qt-at-spi' installed by default. At the time of writing, having that package installed causes InfiniteRicks-qt to crash intermittently. The issue has been reported as launchpad bug 857790, but isn't yet fixed.

Until the bug is fixed, you can remove the qt-at-spi package to work around the problem, though this will presumably disable screen reader functionality for Qt apps:

sudo apt-get remove qt-at-spi
