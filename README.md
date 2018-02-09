# funtoo-reporter
Anonymous reporting tool for Funtoo Linux

Will look for a configuration file at /etc/report.conf it can look like this:

## Configuration for selecting and deselecting which data
## is reported by the funtoo anonymous reporting tool
##
## All options are defaulted to report, you can change an item
## by altering the "y" and "n" to indicate either yes (y) report it
## or no (n) do not report it.
##

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
