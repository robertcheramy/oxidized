# APC Configuration
The configuration of APC Network Management Cards can be downloaded using FTP
and SCP. You can retrieve serial numbers and OS version information through
an SSH connection.

APC OS does not have the ability to display the config.ini within an SSH shell.
A ticket was opened with APC support to enable "cat config.ini"
within an SSH shell, but APC declined to implement this feature.

To overcome this limitation, a capability to run SCP within an SSH connection
has been implemented in Oxidized.

For backward compatibility, there are two models:
- apc_aos: retrieves config.ini using SCP or FTP only
- apcos: retrieves information via SSH and config.ini via SCP

## apc_aos: How do I activate FTP/SCP input?
To download the configuration with FTP or SCP, you must activate it
as an input in the Oxidized configuration. If you don't activate the input,
Oxidized will fail for the node with an error.

The configuration can be done either globally or only for the apc_aos model.

### Global Configuration
The global configuration would look like this. Note that Oxidized will try every
input type in the given order until it succeeds, or it will report a failure.
```yaml
input:
  default: ssh, ftp, scp
```

### Model-Specific Configuration

Configuration for activating the FTP input for apc_aos only:
```yaml
input:
  default: ssh
models:
  apc_aos:
    input: ftp
```

### Setting Specific Credentials
You can also set a specific username and password for apc_aos only:
```yaml
username: default-user
password: default-password
input:
  default: ssh
models:
  apc_aos:
    username: apc-user
    password: apc-password
    input: ftp
```
