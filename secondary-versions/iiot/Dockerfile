ARG IGNITION_VERSION="8.1.36"
FROM bwdesigngroup/ignition-docker:${IGNITION_VERSION:-latest}

USER root

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget

ARG MQTT_DISTRIBUTOR_MODULE_DOWNLOAD_URL="https://files.inductiveautomation.com/third-party/cirrus-link/4.0.21/MQTT-Distributor-signed.modl"
ARG MQTT_DISTRIBUTOR_MODULE_DOWNLOAD_SHA256="210c75ab4a7bfaa0d10f8750a497d427904028db6f4fc1a9ba50a8b1fc8936fe"
ARG MQTT_ENGINE_MODULE_DOWNLOAD_URL="https://files.inductiveautomation.com/third-party/cirrus-link/4.0.21/MQTT-Engine-signed.modl"
ARG MQTT_ENGINE_MODULE_DOWNLOAD_SHA256="e4fb06f96da56f3cf97029c3cbd864c1d91e1ba6677b4241a699804bf33b722c"
ARG MQTT_TRANSMISSION_MODULE_DOWNLOAD_URL="https://files.inductiveautomation.com/third-party/cirrus-link/4.0.21/MQTT-Transmission-signed.modl"
ARG MQTT_TRANSMISSION_MODULE_DOWNLOAD_SHA256="6daf806339f62fc3383fca377533deeeb28d8693842e23d7dc03ea0082bc0c16"

RUN mkdir -p /modules/pre-loaded-modules && \
	wget -q --ca-certificate=/etc/ssl/certs/ca-certificates.crt --referer https://inductiveautomation.com/* -O "/modules/pre-loaded-modules/MQTT-Distributor.modl" "${MQTT_DISTRIBUTOR_MODULE_DOWNLOAD_URL}" && \
	echo "${MQTT_DISTRIBUTOR_MODULE_DOWNLOAD_SHA256}" "/modules/pre-loaded-modules/MQTT-Distributor.modl" | sha256sum -c - && \
	wget -q --ca-certificate=/etc/ssl/certs/ca-certificates.crt --referer https://inductiveautomation.com/* -O "/modules/pre-loaded-modules/MQTT-Engine.modl" "${MQTT_ENGINE_MODULE_DOWNLOAD_URL}" && \
	echo "${MQTT_ENGINE_MODULE_DOWNLOAD_SHA256}" "/modules/pre-loaded-modules/MQTT-Engine.modl" | sha256sum -c - && \
	wget -q --ca-certificate=/etc/ssl/certs/ca-certificates.crt --referer https://inductiveautomation.com/* -O "/modules/pre-loaded-modules/MQTT-Transmission.modl" "${MQTT_TRANSMISSION_MODULE_DOWNLOAD_URL}" && \
	echo "${MQTT_TRANSMISSION_MODULE_DOWNLOAD_SHA256}" "/modules/pre-loaded-modules/MQTT-Transmission.modl" | sha256sum -c - && \
	chown -R ${IGNITION_UID}:${IGNITION_GID} /modules

COPY --chmod=0755 secondary-versions/iiot/iiot-entrypoint-shim.sh /usr/local/bin/

ENTRYPOINT [ "iiot-entrypoint-shim.sh" ]