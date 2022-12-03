# susi

## TODO

### Configuration Validation

- [ ] define workspacce folder (default is CWD)
- [ ] identify devcontainer.json (if none is found take a default one)
- [ ] validate metadata is sufficient

### Environment Creation

- [ ] validate access to container orchestrator
- [ ] execute initializeCommand
- [ ] pull/build/execute image
- [ ] validate the correct creation of the image
- [ ] in case of updateRemoteUserUID perform UID/GID sync
- [ ] create container
- [ ] validate the correct creation of the container
- [ ] apply mount points
- [ ] apply environment variables
- [ ] apply user configuration
- [ ] execute onCreateCommand, updateContentCommand and postCreateCommand
- [ ] apply remote environment variables and user configuration

### Environment Stop

- [ ] stop container

### Environment Resume

- [ ] restart all related containers
- [ ] execute postStartCommand and postAttachCommand

## devcontainer specification

Search a devcontainer.json file in the following directories:
- .devcontainer/devcontainer.json
- .devcontainer.json
- .devcontainer/**/devcontainer.json

There might be more than one devcontainer filer in a project. In this case, the user should be able to select which one to use.

A table with properties:

| Property                    | supported | type       |
|-----------------------------|-----------|------------|
| name                        | no        | general    |
| forwardPorts                | no        | general    |
| portsAttributes             | no        | general    |
| otherPortsAttributes        | no        | general    |
| remoteEnv                   | no        | general    |
| remoteUser                  | no        | general    |
| containerEnv                | no        | general    |
| containerUser               | no        | general    |
| updateRemoteUserUID         | no        | general    |
| userEnvProbe                | no        | general    |
| overrideCommand             | no        | general    |
| shutdownAction              | no        | general    |
| init                        | no        | general    |
| privileged                  | no        | general    |
| capAdd                      | no        | general    |
| securityOpt                 | no        | general    |
| mounts                      | no        | general    |
| features                    | no        | general    |
| overrideFeatureInstallOrder | no        | general    |
| customizations              | no        | general    |
| image                       | no        | image      |
| build.dockerfile            | no        | image      |
| build.context               | no        | image      |
| build.args                  | no        | image      |
| build.target                | no        | image      |
| build.cacheFrom             | no        | image      |
| appPort                     | no        | image      |
| workspaceMount              | no        | image      |
| workspaceFolder             | no        | image      |
| runArgs                     | no        | image      |
| dockerComposeFile           | no        | compose    |
| service                     | no        | compose    |
| runServices                 | no        | compose    |
| workspaceFolder             | no        | compose    |
| initializeCommand           | no        | lifecycle  |
| onCreateCommand             | no        | lifecycle  |
| updateContentCommand        | no        | lifecycle  |
| postCreateCommand           | no        | lifecycle  |
| postStartCommand            | no        | lifecycle  |
| postAttachCommand           | no        | lifecycle  |
| waitFor                     | no        | lifecycle  |
| hostRequirements.cpus       | no        | host       |
| hostRequirements.memory     | no        | host       |
| hostRequirements.storage    | no        | host       |
| label                       | no        | port       |
| protocol                    | no        | port       |
| onAutoForward               | no        | port       |
| requireLocalPort            | no        | port       |
| elevateIfNeeded             | no        | port       |

### Environment variables

Environment variables should be available in the following properties:

| Variable                            | supported | type       |
|-------------------------------------|-----------|------------|
| ${localEnv:VARIABLEN_NAME}          | no        | general    |
| ${containerEnv:VARIABLE_NAME}       | no        | general    |
| ${localWorkspaceFolder}             | no        | general    |
| ${containerWorkspaceFolder}         | no        | general    |
| ${localWorkspaceFolderBasename}     | no        | general    |
| ${containerWorkspaceFolderBasename} | no        | general    |
| ${devcontainerId}                   | no        | general    |

### Features

Consideration of features needs to be done later.