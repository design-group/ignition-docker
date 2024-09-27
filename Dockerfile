ARG IGNITION_VERSION="8.1.43"
FROM inductiveautomation/ignition:${IGNITION_VERSION:-latest}

USER root

ENV IGNITION_VERSION=${IGNITION_VERSION:-8.1.43}
ENV WORKING_DIRECTORY=${WORKING_DIRECTORY:-/workdir}
ENV ACCEPT_IGNITION_EULA="Y"
ENV GATEWAY_ENCODING_KEY_FILE=${GATEWAY_ENCODING_KEY_FILE:-/gateway-encoding-key}
ENV GATEWAY_ADMIN_USERNAME=${GATEWAY_ADMIN_USERNAME:-admin}
ENV GATEWAY_ADMIN_PASSWORD=${GATEWAY_ADMIN_PASSWORD:-password}
ENV IGNITION_EDITION=${IGNITION_EDITION:-standard}
ENV GATEWAY_MODULES_ENABLED=${GATEWAY_MODULES_ENABLED:-alarm-notification,allen-bradley-drivers,bacnet-driver,opc-ua,perspective,reporting,tag-historian,web-developer}
ENV IGNITION_UID=${IGNITION_UID:-1000}
ENV IGNITION_GID=${IGNITION_GID:-1000}
ENV DEVELOPER_MODE=${DEVELOPER_MODE:-N}
ENV GATEWAY_PUBLIC_ADDRESS=${GATEWAY_PUBLIC_ADDRESS:-localhost}
ENV GATEWAY_PUBLIC_HTTP_PORT=${GATEWAY_PUBLIC_HTTP_PORT:-8088}
ENV GATEWAY_PUBLIC_HTTPS_PORT=${GATEWAY_PUBLIC_HTTPS_PORT:-8043}
ENV DISABLE_QUICKSTART=${DISABLE_QUICKSTART:-true}
ENV HANDLE_EXISTING_PASSWORDS=${HANDLE_EXISTING_PASSWORDS:-true}

ENV CONFIG_PERMISSIONS=${CONFIG_PERMISSIONS:-Authenticated/Roles/Administrator}
ENV STATUS_PAGE_PERMISSIONS=${STATUS_PAGE_PERMISSIONS:-Authenticated/Roles/Administrator}
ENV HOME_PAGE_PERMISSIONS=${HOME_PAGE_PERMISSIONS:-}
ENV DESIGNER_PERMISSIONS=${DESIGNER_PERMISSIONS:-Authenticated/Roles/Administrator}
ENV PROJECT_CREATION_PERMISSIONS=${PROJECT_CREATION_PERMISSIONS:-}

ENV SYMLINK_PROJECTS=${SYMLINK_PROJECTS:-true}
ENV SYMLINK_THEMES=${SYMLINK_THEMES:-true}
ENV ADDITIONAL_DATA_FOLDERS=${ADDITIONAL_DATA_FOLDERS:-}

RUN apt-get update && apt-get install -y sqlite3 unzip zip openssl vim-common jq file && rm -rf /var/lib/apt/lists/*

# Copy in a base gateway backup to seed, incase the user doesnt
COPY build/base.gwbk /base.gwbk

# Create the gateway encoding key with the right permissions
RUN touch /gateway-encoding-key && chown ignition:ignition /gateway-encoding-key

# Copy in the entrypoint shim and scripts
COPY --chmod=0755 ./scripts/*.sh /usr/local/bin/
COPY --chmod=0755 ./entrypoint-shim.sh /usr/local/bin/

ENTRYPOINT [ "entrypoint-shim.sh" ]