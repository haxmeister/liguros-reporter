# funtoo-reporter
###### Anonymous reporting tool for Funtoo Linux

### Installation:
After cloning this git certain modules will need to be installed for perl

1. 'Search::Elasticsearch' which is available in CPAN
2. JSON which is available in CPAN or in the gentoo and funtoo repositories as 'dev-perl/JSON'

### Operation:
**The reporting tool is intended to run with root privileges for access to key system files. Use the method most appropriate on your system**

**Just launching the program will show you a help menu:**

'./report'

```
Funtoo anonymous data reporting tool usage:

report send              Send the report to funtoo's data collection
report show-json         Show the output that will be sent, in JSON format
report help              Show this help list

Output can be ommitted by modifying the /etc/report.conf file
```
**help shows you the same output:**

'./report help'

**To see what data the report is generating use the show-json option:**

'./report show-json'

**You may get an error that no config file is found at /etc/report.conf and it will then try to create one with all available options turned on:**

```
Could not open file the configuration file at /etc/report.conf
Attempting to create one...

A config file has been generated at /etc/report.conf
Please review this file for errors.

```
**You can send your report to the elastic search database using the send option which will output nothing on the console if it is successful:**

'./report send'

### Configuration:

The reporting tool is completely anonymous and the individual categories that are in the report can be turned off or on by editing the config file. The config file is located at /etc/report.conf and will be autogenerated by the script if one is not present. All lines of the config file that are empty or start with # are ignored. The rest are read but may be ignored if they do not match any expected setting. You can manually change the settings from 'y' to 'n' to disable a particular category. Using the show-json option, you can confirm that this portion of the report is not being output.. since the show-json option actually shows exactly what is reported to elasticsearch. 

**Here is an example of all possible values in the config file**

```perl
# To report cpu info which includes clock speed, model name,
# and cpu cores
cpu-info:y

# To report memory info which includes the amount of free memory,
# the amount of memory available, total amount of swap space,
# and the amount of free swap space
mem-info:y

# To report kernel info including O.S. type, release and version
kernel-info:y

# Allows the reporter to search your /boot directory and list
# any kernels it finds
# (limited to kernel names that start with "kernel" or "vmlinuz")
boot-dir-info:y

# To report versions of key softwares on your system including
# portage, ego, python, gcc, and glibc
version-info:y

# To report the contents of /var/lib/portage/world
world-info:y

# To report profiles information
# the same as epro show-json
profile-info:y

# To report kit versions as reported by ego
# extracted from ego kit show
kit-info:y

# To report system chassis type and model
chassis-info:y

# To report all installed packages (takes a few secs)
installed-pkgs:y

```
