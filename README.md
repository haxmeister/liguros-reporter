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
