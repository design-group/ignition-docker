# bwdesigngroup/ignition-docker

[![8.1 Build Status](https://github.com/thirdgen88/ignition-docker/actions/workflows/multibuild-8.1.yml/badge.svg)](https://github.com/design-group/ignition-docker/actions)
[![Docker Stars](https://img.shields.io/docker/stars/bwdesigngroup/ignition-docker.svg)](https://hub.docker.com/r/bwdesigngroup/ignition-docker)
[![Docker Pulls](https://img.shields.io/docker/pulls/bwdesigngroup/ignition-docker.svg)](https://hub.docker.com/r/bwdesigngroup/ignition-docker)

## Design Group Template Image

The purpose of this image is to provide a quick way to spin up docker containers that include some necessary creature comforts for version control, theme management, and easy interaction with the required file system components for an Ignition gateway.

This image is automatically built for versions 8.1.13-8.1.37, new versions will be updated, but any features are subject to change with later versions. Upon a new pull request, if a valid build file is modified, it will trigger a build test pipeline that verifies the image still operates as expected.

If using a Windows device, you will want to [Set up WSL](docs/setting-up-wsl.md)

___

## Getting the Docker Image

If you're looking at this repository from GitHub, note that the docker image is actually `bwdesigngroup/ignition-docker`, not `design-group/ignition-docker`.

When pulling the docker image, note that using the copy link from the home page (`docker pull bwdesigngroup/ignition-docker`) will automatically pull the most recent version of Ignition configured in the image. For example `:latest` may pull version `8.1.37` as of the time of writing.

## File Access

This custom build creates a symlink in the `/workdir` directory to a few of the components in Ignition's `data` directory. This allows you to easily access the files on the host system, and simplifies the necessary `.gitignore` for a project. The following items are symlinked by default, and these are the environment variables that enable them:
| Symlink Path | Environment Variable |
| --- | --- |
| `/usr/local/bin/ignition/data/projects` | `SYMLINK_PROJECTS` |
| `/usr/local/bin/ignition/data/modules` | `SYMLINK_THEMES` |
| `/usr/local/bin/ignition/data/logback.xml` | `SYMLINK_LOGBACK` |

To disable one of the symlinks, set the environment variable to `false`. For example, to disable the symlink to the `projects` directory, set `SYMLINK_PROJECTS=false`

### Note for Windows/Linux Users

In order for the symlinks to work, you must first create an empty folder adjacent to the `docker-compose.yml` file that has the same name as the desired bind mount. On Windows/Linux docker will automatically do everything as `root`, so without doing this the created file will be owned by `root:root` instead of `user:user`. On a Mac, this is not necessary, MacOS ftw.

___

## Customizations

This is a derived image of the `inductiveautomation/ignition` image. Please see the [Ignition Docker Hub](https://hub.docker.com/r/inductiveautomation/ignition) for more information on the base image. This image should be able to take all arguments provided by the base image, but has not been tested.

### Environment Variables

This image also preloads the following environment variables by default:
| Environment Variable | Min-Version | Value |
| --- | --- | --- |
| `ACCEPT_IGNITION_EULA` | 8.1.13 | `Y` |
| `GATEWAY_ADMIN_USERNAME` | 8.1.13 | `admin` |
| `GATEWAY_ADMIN_PASSWORD` | 8.1.13 | `password` |
| `IGNITION_EDITION` | 8.1.13 | `standard` |
| `GATEWAY_MODULES_ENABLED` | 8.1.17 | `alarm-notification,allen-bradley-drivers,bacnet-driver,opc-ua,perspective,reporting,tag-historian,web-developer` |
| `IGNITION_UID` | 8.1.13 | `1000` |
| `IGNITION_GID` | 8.1.13 | `1000` |
| `PROJECT_SCAN_FREQUENCY` | 8.1.13 | `10` |
| `SYMLINK_LOGBACK` | 8.1.13 | `true` |
| `SYMLINK_PROJECTS` | 8.1.13 | `true` |
| `SYMLINK_THEMES` | 8.1.13 | `true` |
| `SYMLINK_GITIGNORE` | 8.1.13 | `true` |
| `ADDITIONAL_DATA_FOLDERS` | 8.1.13 | `""` |
| `DEVELOPER_MODE` | 8.1.13 | `N` |
| `ENABLE_LOCALTEST_ADDRESS` | 8.1.13 | `Y` |
| `DISABLE_QUICKSTART` | 8.1.23 | `true` |

### logback.xml

The included `logback.xml` file is a default file, it is just mapped into the working directory so that it can be customized if desired.

### Additional Config Folders

Added an environment variable that allows the user to map application config files located in the `data` directory into the `/workdir`. This is customized by providing a comma separated list of folders in a string to the environment variable. For example, to map the `data/notifications` and `data/configs` folders, set the environment variable `ADDITIONAL_DATA_FOLDERS=notifications,configs` to the `docker-compose.yml` file.

### Secondary Images

This image also includes a few other images that are useful for development that involves third party igniiton modules being pre-installed.

#### ignition-docker-iiot

This image is a derivative of the `inductiveautomation/ignition` image, and includes the following modules pre-installed:

	- `MQTT Transmission`
	- `MQTT Engine`
	- `MQTT Distributor`

It takes the `IIOT_MODULES_ENABLED` environment variable that is a comma separated list of modules to enable. For example, to enable all three modules, set the environment variable `IIOT_MODULES_ENABLED=mqtt-transmission,mqtt-engine,mqtt-distributor` to the `docker-compose.yml` file. This image only supports version 8.1.36, if a different version is needed, please open an issue.

#### ignition-docker-mes

This image is a derivative of the `inductiveautomation/ignition` image, and includes the following modules pre-installed:

- `WebService`
- `Production`
- `Settings and Changeover`
- `Batch`
- `SPC`
- `Document Management`
- `OEE Downtime`
- `Track and Trace`

It takes the `MES_MODULES_ENABLED` environment variable that is a comma separated list of modules to enable. For example, to enable the Settings and Changeover and Batch Procedure modules, set the environment variable `MES_MODULES_ENABLED=production,batch` to the `docker-compose.yml` file. This image only supports version 8.1.35, if a different version is needed, please open an issue.

### Third Party Modules

Any additional modules outside of the native ignition ones that want to be added can be mapped into the `/modules` folder in the container. This is done by adding the following to the `volumes` section of the `docker-compose.yml` file:

	```yaml
		volumes:
		- ./my-local-modules:/modules
	```

Due to the way module onboarding works, in order for it to take effect, you must restart the container after its initial creation. This can be done by running `docker-compose restart` from the directory containing the `docker-compose.yml` file.

___

### Example docker-compose file

	```yaml
	services:
	  gateway:
		  image: bwdesigngroup/ignition-docker:8.1.31
		  ports:
		  - 80:8088
		  # # In order to use this volume, you must first create the directory `data-folder` next to the docker-compose.yml file
		  # volumes:
		  #   - ./data-folder:/workdir
		  # environment:
		  #   - ADDITIONAL_DATA_FOLDERS=one-folder,other-folder
	```

___

### Contributing

This repository uses [pre-commit](https://pre-commit.com/) to enforce code style. To install the pre-commit hooks, run `pre-commit install` from the root of the repository. This will run the hooks on every commit. If you would like to run the hooks manually, run `pre-commit run --all-files` from the root of the repository.

### Local Feature Testing

In order to test your features, you can use the following procedure to build and run your own images:

1. Open a terminal or command prompt on your host machine.
2. Navigate to the directory containing both `Dockerfile` and the `docker-bake.hcl`
3. Run `docker build --file Dockerfile -t <your-image-name>  . | docker bake -f docker-bake.hcl -`
4. In a new directory, make a `docker-compose.yml` file using the Example docker-compose file above substituting the value for `image` for `<your-image-name>`. See example below:

		services:
			gateway:
				image: <your-image-name>
				ports:
					- 80:8088

5. Run `docker-compose up -d` in the directory containing your `docker-compose.yml` file.

### Building a pushing a specific version

1. Open a terminal or command prompt on your host machine.
2. Navigate to the directory containing both `Dockerfile` and the `docker-bake.hcl`
3. Run `docker buildx bake --file ./docker-bake.hcl <build-target> --push`

### Requests

If you have any requests for additional features, please feel free to [open an issue](https://github.com/design-group/ignition-docker/issues/new/choose) or submit a pull request.

### Shoutout

A big shoutout to [Inductive Automation](https://inductiveautomation.com/) for providing the base image and Ignition software, and [Kevin Collins](https://github.com/thirdgen88) for the original inspiration and support for this image.

