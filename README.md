<img align="right" src="https://cdn.datafloq.com/cache/cc/f0/ccf05eed78864d4e31798f90a528a408.png" width="150" />

# Aerospike Cluster Backup

***
**Table of Contents:**
1. [Install required packages](#install-required-packages)  
2. [Usage](#usage)  
3. [Automate the backup](#automate-the-backup)  
4. [Restore](#restore)  
***

### Description
Aerospike provides the ability to backup and restore your cluster data.
Under normal circumstances, data replication (within a cluster) and cross data center replication (XDR) ensure that data is not lost even when there are hardware failures or network outages.
However, it is good practice to periodically create backups for easier recovery from catastrophic data center failures or administrative accidents.

This how-to tutorial shows how to automate scheduled backups of Aerospike database.  
The script can store backups on S3 and local copies, according to your requirement.

Based on official backup/restore utilities (asbackup). Requires: AWS CLI and Tar packages.

Key features:
* Fault tolerant
* Stores locally and on S3
* Backups rotation
* Compression

### Getting Started
* Setup a bucket on AWS S3
* Install required packages
  
It's highly recommended to set a lifecycle policy on the bucket to expire files older than X days.  
In my case, I prefer to archive older backups to Glacier, which is much less expensive storage.  

#### Install required packages
On Debian like:
```
# install aws command line
sudo apt install awscli
```

On RedHat like:
```
# install python and pip
sudo yum install epel-release
sudo yum install python python-pip

# install aws command line
sudo pip install --upgrade --user awscli
```

*Outside AWS, make sure you provide proper credentials, using `aws configure` command*

Let's verify we have access to S3. This command will show you all your S3 buckets:
```
aws s3 ls
```

Clone this repository:
```
git clone https://github.com/sysboss/aerospike_backup.git
```

### Usage
```
usage: ./aerospike-backup.sh options

OPTIONS:
    -a    Aerospike namespace to backup
    -b    AWS S3 Bucket Name
    -w    Work directory path (default: /mnt)
    -l    Log to file (default: STDOUT)
    -k    Keep local copies (default: 0)
    -r    AWS S3 Region (optional)
    -p    Path / Folder inside the bucket (optional)
```

### Automate the backup
To schedule automatic backup at 01:05 AM, add the following line to your crontab:
```
5 1 * * *    ubuntu    /mnt/aerospike-backup.sh -a ${AppNamespace} -b ${S3-Backups-Bucket} -k 7

```
*This will upload backups to ${S3-Backups-Bucket} bucket and keep 7 local copies of ${AppNamespace} namespace*

### Restore
Use `asrestore` to restore data from backup. See documentation for more datails: https://www.aerospike.com/docs/tools/backup/asrestore.html
