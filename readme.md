# bwdesigngroup/ignition-docker

[![8.1 Build Status](https://github.com/design-group/ignition-docker/actions/workflows/build-individual.yml/badge.svg)](https://github.com/design-group/ignition-docker/actions)
[![Docker Stars](https://img.shields.io/docker/stars/bwdesigngroup/ignition-docker.svg)](https://hub.docker.com/r/bwdesigngroup/ignition-docker)
[![Docker Pulls](https://img.shields.io/docker/pulls/bwdesigngroup/ignition-docker.svg)](https://hub.docker.com/r/bwdesigngroup/ignition-docker)

## Design Group Template Image

The purpose of this image is to provide a quick way to spin up docker containers that include some necessary creature comforts for version control, theme management, and easy interaction with the required file system components for an Ignition gateway.

This image is automatically built for the latest version of Ignition, new versions will be updated, but any features are subject to change with later versions. Upon a new pull request, if a valid build file is modified, it will trigger a build test pipeline that verifies the image still operates as expected.

Previous versions of Ignition can be built with the `workflows/build-multiple.yml` workflow. This will build the image for all versions in the range provided.

___

## Getting the Docker Image

If you're looking at this repository from GitHub, note that the docker image is actually `bwdesigngroup/ignition-docker`, not `design-group/ignition-docker`.

When pulling the docker image, note that using the copy link from the home page (`docker pull bwdesigngroup/ignition-docker`) will automatically pull the most recent version of Ignition configured in the image. For example `:latest` may pull version `8.1.42` as of the time of writing.

## File Access

This custom build creates a symlink in the `/workdir` directory to a few of the components in Ignition's `data` directory. This allows you to easily access the files on the host system, and simplifies the necessary `.gitignore` for a project. The following items are symlinked by default, and these are the environment variables that enable them:
| Symlink Path                            | Environment Variable |
| --------------------------------------- | -------------------- |
| `/usr/local/bin/ignition/data/projects` | `SYMLINK_PROJECTS`   |
| `/usr/local/bin/ignition/data/modules`  | `SYMLINK_THEMES`     |

To disable one of the symlinks, set the environment variable to `false`. For example, to disable the symlink to the `projects` directory, set `SYMLINK_PROJECTS=false`

### Note for Windows/Linux Users

In order for the symlinks to work, you must first create an empty folder adjacent to the `docker-compose.yml` file that has the same name as the desired bind mount. On Windows/Linux docker will automatically do everything as `root`, so without doing this the created file will be owned by `root:root` instead of `user:user`. On a Mac, this is not necessary, MacOS ftw.

___

## Customizations

This is a derived image of the `inductiveautomation/ignition` image. Please see the [Ignition Docker Hub](https://hub.docker.com/r/inductiveautomation/ignition) for more information on the base image. This image should be able to take all arguments provided by the base image, but has not been tested.

### Environment Variables

This image also preloads the following environment variables by default:
| Environment Variable           | Min-Version | Value                                                                                                             |
| ------------------------------ | ----------- | ----------------------------------------------------------------------------------------------------------------- |
| `ACCEPT_IGNITION_EULA`         | 8.1.13      | `Y`                                                                                                               |
| `GATEWAY_ADMIN_USERNAME`       | 8.1.13      | `admin`                                                                                                           |
| `GATEWAY_ADMIN_PASSWORD`       | 8.1.13      | `password`                                                                                                        |
| `IGNITION_EDITION`             | 8.1.13      | `standard`                                                                                                        |
| `GATEWAY_MODULES_ENABLED`      | 8.1.17      | `alarm-notification,allen-bradley-drivers,bacnet-driver,opc-ua,perspective,reporting,tag-historian,web-developer` |
| `IGNITION_UID`                 | 8.1.13      | `1000`                                                                                                            |
| `IGNITION_GID`                 | 8.1.13      | `1000`                                                                                                            |
| `PROJECT_SCAN_FREQUENCY`       | 8.1.13      | `10`                                                                                                              |
| `SYMLINK_PROJECTS`             | 8.1.13      | `true`                                                                                                            |
| `SYMLINK_THEMES`               | 8.1.13      | `true`                                                                                                            |
| `ADDITIONAL_DATA_FOLDERS`      | 8.1.13      | `""`                                                                                                              |
| `DEVELOPER_MODE`               | 8.1.13      | `N`                                                                                                               |
| `DISABLE_QUICKSTART`           | 8.1.23      | `true`                                                                                                            |
| `GATEWAY_ENCODING_KEY`         | 8.1.38      | If not set, will be generated for password injection to the db.                                                   |
| `GATEWAY_ENCODING_KEY_FILE`    | 8.1.38      | If not set, will be generated for password injection to the db.                                                   |
| `SYSTEM_USER_SOURCE`           | 8.1.13      | `""`                                                                                                              |
| `SYSTEM_IDENTITY_PROVIDER`     | 8.1.13      | `""`                                                                                                              |
| `HOMEPAGE_URL`                 | 8.1.13      | `""`                                                                                                              |
| `DESIGNER_AUTH_STRATEGY`       | 8.1.13      | `""`                                                                                                              |
| `CONFIG_PERMISSIONS`           | 8.1.13      | `""`, See [Permission Syntax](#permission-syntax) for help.                                                       |
| `STATUS_PAGE_PERMISSIONS`      | 8.1.13      | `""`, See [Permission Syntax](#permission-syntax) for help.                                                       |
| `HOME_PAGE_PERMISSIONS`        | 8.1.13      | `""`, See [Permission Syntax](#permission-syntax) for help.                                                       |
| `DESIGNER_PERMISSIONS`         | 8.1.13      | `""`, See [Permission Syntax](#permission-syntax) for help.                                                       |
| `PROJECT_CREATION_PERMISSIONS` | 8.1.13      | `""`, See [Permission Syntax](#permission-syntax) for help.                                                       |
| `OPC_SERVER_PASSWORD`          | 8.1.38      | `""`, if the password cannot be decoded with the `GATEWAY_ENCODING_KEY`, then it will default to `password`       |

### Permission Syntax

The permissions are a comma separated list of permissions that can be set for the corresponding property. The permission start with the permission type, followed by a comma, and then the permission values in a comma seperated list. For example, to set the `CONFIG_PERMISSIONS` value to `Authenticated/Role/Administrator` AND also `Authenticated/Role/Developer`, you would set the `CONFIG_PERMISSIONS` environment variable to `AllOf,Authenticated/Role/Administrator,Authenticated/Role/Developer`.

### Additional Config Folders

Added an environment variable that allows the user to map application config files located in the `data` directory into the `/workdir`. This is customized by providing a comma separated list of folders in a string to the environment variable. For example, to map the `data/notifications` and `data/configs` folders, set the environment variable `ADDITIONAL_DATA_FOLDERS=notifications,configs` to the `docker-compose.yml` file.

### Secondary Images

The [previous version of this repository](https://github.com/bwdesigngroup/ignition-docker-legacy) used to include versions for `-iiot` and `-mes`. This essentially just mapped in the corresponding modules, however it was finicky, and didnt always work as expected because module versions for Sepasoft aren't identical to Ignition versions. 

Because of this, the decision was made to remove these images, and instead the best practice is to use the [Third Party Modules](#third-party-modules) section to map in the modules you need. This allows for more flexibility and control over the modules that are being used and their versions.

### Third Party Modules

Any additional modules outside of the native ignition ones that want to be added can be mapped into the `/modules` folder in the container. This is done by adding the following to the `volumes` section of the `docker-compose.yml` file:

```yaml
volumes:
  - ./my-local-modules:/modules
```

### Database Connections

Requires version 8.1.38 or later, due to the need for the `GATEWAY_ENCODING_KEY` environment variable.

Database connections can be added by mapping in the SQL files to the `/init-db-connections` folder in the container. 

The following syntax is expected in `.json` files to add a database connection:

```json
{
	"name": "ExampleMSSQL",
	"type": "MSSQL",
	"description": "Example Microsoft SQL Server Connection",
	"connect_url": "jdbc:sqlserver://myServer:1433\\MSSQLSERVER",
	"username": "TheUsername",
	"password": "ThePassword",
	"connection_props": "databaseName=exampledb"
}
```

Appropriate `type`'s are: `MSSQL`, `POSTGRES`, `SQLITE`, `MYSQL`, `ORACLE`, `MARIADB` 

This functionality will either insert or update existing database connections based off the name of the connection.

### IDP Adapters

IDP Adapters can be added by mapping in the IDP Adapter files to the `/init-idp-adapters` folder in the container. 

The feature expects the syntax in a `.json` file exported by the native Ignition IDP Adapter export feature. To get an export, go to the IDP Configuration page and select `More > Export` on the pre-configured provider.

This will either insert or update existing IDP Adapters based off the name of the adapter.

### Adding Images to the IDB

Images can be added to the IDB by mapping in the image files to the `/idb-images` folder in the container. 

The feature will search through any `.png`, `.jpg`, or `.jpeg` files in the directory and add them to the IDB. The name of the image will be the name of the file, and the path will be the path of the file from within the `/idb-images` directory. This will either insert or update existing images based off the name of the image.

### Tag Providers

Tag Providers can be added by mapping in the Tag Provider files to the `/tag-providers` folder in the container. 

The following syntax is expected in `.json` files to add a tag provider. The required fields vary based on the `type_id`:

1. Standard Tag Provider (Realtime):

```json
{
	"name": "ExampleLocalRealtimeProvider",
	"description": "Default tag provider",
	"type_id": "STANDARD"
}
```

1. Remote Tag Provider (GAN) (Realtime):

```json
{
	"name": "ExampleRemoteRealtimeProvider",
	"description": "An Example Remote Realtime Provider",
	"type_id": "gantagprovider",
	"server_name": "RemoteGatewaysNameHere",
	"provider_name": "TheProvider"
}
```

1. DB Table Historian (Historical):

```json
{
	"name": "ExampleDBTable",
	"description": "DB Table Historian example",
	"type_id": "widedb",
	"datasource_name": "ExampleMSSQL"
}
```

1. Internal Historian (Historical):

```json
{
	"name": "ExampleInternal",
	"description": "Internal Historian example",
	"type_id": "EdgeHistorian"
}
```

1. Remote History Provider (Historical):

```json
{
	"name": "ExampleRemote",
	"description": "Remote History Provider example",
	"type_id": "RemoteHistorian",
	"server_name": "RemoteGatewaysNameHere",
	"provider_name": "TheProvider"
}
```

1. Tag History Splitter (Historical):

```json
{
	"name": "ExampleHistorySplitter",
	"description": "Tag History Splitter example",
	"type_id": "SplittingProvider",
	"connection_a": "exampleremote",
	"connection_b": "ExampleInternal"
}
```

For the `type_id` field, the following options are available:

| Type ID            | Type of Provider           | Strategy    | Additional Required Fields |
| ------------------ | -------------------------- | ----------- | -------------------------- |
| `STANDARD`         | Standard Tag Provider      | Realtime    | None |
| `gantagprovider`   | Remote Tag Provider (GAN)  | Realtime    | `server_name`, `provider_name` |
| `widedb`           | DB Table Historian         | Historical  | `datasource_name` |
| `EdgeHistorian`    | Internal Historian         | Historical  | None |
| `RemoteHistorian`  | Remote History Provider    | Historical  | None |
| `SplittingProvider`| Tag History Splitter       | Historical  | `connection_a`, `connection_b` |

The following fields have default values and are optional for all provider types:

- `enabled`: true
- `allow_backfill`: true
- `enable_tag_reference_store`: true
- `read_permissions`: "AllOf"
- `write_permissions`: "AllOf"
- `edit_permissions`: "AllOf"

Additional optional fields for specific provider types:

- For `RemoteHistorian`:
  - `allow_storage`: true
  - `max_grouping`: 0

The script will automatically determine if the provider is realtime or historical based on the `type_id`.

This will either insert or update existing tag providers based on the name of the provider.

### Co-Branding

Requires version 8.1.20 or later.

Co-Branding properties can be set by mapping in the Co-Branding files to the `/co-branding` folder in the container. 

The following syntax is expected in `.json` files to set a co-branding property:

```json
{
	"enabled": true,
	"backgroundColor": "#FFBF00",
	"textColor": "#000000",
	"buttonColor": "#FFBF00",
	"buttonTextColor": "#000000",
	"logoPath": "/co-branding/icon160.png",
	"faviconPath": "/co-branding/icon180.png",
	"appIconPath": "/co-branding/icon180.png"
}
```

The images need to be either `.png`, or `.svg` files. The paths are relative to the `/co-branding` directory. This will either insert or update existing co-branding properties.

### Localization

Localization files can be added by mapping in the localization files to the `/localization` folder in the container. The script supports the native `.properties` and `.xml` export file formats for localization.

#### Properties File Format

For `.properties` files, use the following format:

```properties
#Locale: es
hello=hola
car=coche
```

The first line must specify the locale using `#Locale: <locale_code>`.

#### XML File Format

For `.xml` files, use the following format:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">
<properties>
<comment>Locale: es</comment>
<entry key="hello">hola</entry>
<entry key="car">coche</entry>
</properties>
```

The `<comment>` tag must specify the locale using `Locale: <locale_code>`.

#### Localization Settings

You can customize the localization settings by creating a `properties.json` file in the `/localization` folder. The file should have the following structure:

```json
{
	"caseInsensitive": false,
	"ignoreWhitespace": false,
	"ignorePunctuation": false,
	"ignoreTags": false
}
```

All fields are optional and default to `false` if not specified.

#### Usage

To use the localization feature:

1. Create a folder named `localization` in your project directory.
2. Add your `.properties` and/or `.xml` localization files to this folder.
3. Optionally, add a `properties.json` file to customize localization settings.
4. In your `docker-compose.yml` file, add a volume mapping for the localization folder:

```yaml
volumes:
  - ./localization:/localization
```

The localization files will be processed when the container starts, and the translations will be available in your Ignition projects.

___

### Example docker-compose file

```yaml
services:
  gateway:
	image: bwdesigngroup/ignition-docker:8.1.31
	# # In order to use this volume, you must first create the directory `data-folder` next to the docker-compose.yml file
	# volumes:
	#   - ./data-folder:/workdir
	#   - ./init-sql:/init-sql
	#   - ./modules:/modules
	#   - ./secrets/gateway-encoding-key:/gateway-encoding-key
	#   - ./init-db-connections:/init-db-connections
	#   - ./init-idp-adapters:/init-idp-adapters
	#   - ./tag-providers:/tag-providers
	#   - ./idb-images:/idb-images
	#   - ./co-branding:/co-branding
	#   - ./localization:/localization
	# environment:
	#   - ADDITIONAL_DATA_FOLDERS=one-folder,other-folder
```

Note the addition of the `./localization:/localization` volume mapping for the localization feature.

___

### Contributing

This repository uses [pre-commit](https://pre-commit.com/) to enforce code style. To install the pre-commit hooks, run `pre-commit install` from the root of the repository. This will run the hooks on every commit. If you would like to run the hooks manually, run `pre-commit run --all-files` from the root of the repository.

### Local Feature Testing

In order to test your features, you can use the following procedure to build and run your own images:

1. Open a terminal or command prompt on your host machine.
2. Navigate to the directory containing both `Dockerfile` and the `docker-bake.hcl`
3. Run `docker build --file Dockerfile -t <your-image-name>  . | docker bake -f docker-bake.hcl -`
4. In a new directory, make a `docker-compose.yml` file using the Example docker-compose file above substituting the value for `image` for `<your-image-name>`. See example below:

	```yaml
	services:
		gateway:
			image: <your-image-name>
			ports:
				- 80:8088
	```

5. Run `docker-compose up -d` in the directory containing your `docker-compose.yml` file.

### Building a pushing a specific version

1. Open a terminal or command prompt on your host machine.
2. Navigate to the directory containing both `Dockerfile` and the `docker-bake.hcl`
3. Run `docker buildx bake --file ./docker-bake.hcl <build-target> --push`

### Requests

If you have any requests for additional features, please feel free to [open an issue](https://github.com/design-group/ignition-docker/issues/new/choose) or submit a pull request.

### Shoutout

A big shoutout to [Inductive Automation](https://inductiveautomation.com/) for providing the base image and Ignition software, and [Kevin Collins](https://github.com/thirdgen88) for the original inspiration and support for this image, as well as inspiration for the `register-password.sh` and `register-module.sh` scripts!
