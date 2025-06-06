#!/bin/bash

# # set default values
USE_ARCH=${1:--x86_64}
USE_SECURITY=${2:--}
USE_SHA1=${3:-main}
TEST_STRATEGY=${4:-}
DELAYED_START=${5:-false}

# # x86_64 or arm64
[ "$USE_ARCH" = "arm64" ] && USE_ARM64="-arm64"

# # security or no security
[ "$USE_SECURITY" != '-security-' ] && USE_NO_SECURITY="-no-secty"

# # pre-release or other release
mkdir -p tmp
# generate single file docker-compose.yml for target configuration without
# default device services, i.e. no device-virtual service
./sync-compose-file.sh "${USE_SHA1}" "${USE_NO_SECURITY}" "${USE_ARM64}" "-taf"
cp docker-compose-taf${USE_NO_SECURITY}${USE_ARM64}.yml docker-compose.yml

if [ "${TEST_STRATEGY}" = "integration-test" ]; then
  # sync compose file for mqtt message bus
  ./sync-compose-file.sh "${USE_SHA1}" "${USE_NO_SECURITY}" "${USE_ARM64}" "-taf" "" "-mqtt-bus"
  cp docker-compose-taf${USE_NO_SECURITY}-mqtt-bus${USE_ARM64}.yml docker-compose-mqtt-bus.yml
  # Set Compose files variable
  COMPOSE_FILE="docker-compose docker-compose-mqtt-bus"
else
  COMPOSE_FILE="docker-compose"
fi

for compose in ${COMPOSE_FILE}; do
  for profile in device-virtual device-modbus; do
    sed -n "/^\ \ ${profile}:/,/^  [a-z].*:$/p" ${compose}.yml | sed '$d' > tmp/${profile}.yml  # print device-service
    sed -i 's/\CONFIG_DIR_PLACE_HOLDER/${CONFIG_DIR}/g' tmp/${profile}.yml
    sed -i "s/\PROFILE_VOLUME_PLACE_HOLDER/\${WORK_DIR}\/TAF\/config\/${profile}/g" tmp/${profile}.yml
    # Enable Delayed Start
    if [ "${TEST_STRATEGY}" = "integration-test" ] && [ "${USE_SECURITY}" = '-security-' ] \
      && [ "${DELAYED_START}" = 'true' ]; then
      sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ SECRETSTORE_RUNTIMETOKENPROVIDER_ENABLED: "true"' tmp/${profile}.yml
      sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ SECRETSTORE_RUNTIMETOKENPROVIDER_HOST: edgex-security-spiffe-token-provider' tmp/${profile}.yml
      sed -i "s/\/tmp\/edgex\/secrets\/${profile}/\/tmp\/edgex\/secrets\/spiffe\/public/g" tmp/${profile}.yml
    fi
    sed -i "/^\ \ ${profile}:/,/^  [a-z].*:$/{//!d}; /^\ \ ${profile}:/d" ${compose}.yml
    sed -i "/services:/ r tmp/${profile}.yml" ${compose}.yml
  done

  # Enable Delayed Start
  if [ "${TEST_STRATEGY}" = "integration-test" ] && [ "${USE_SECURITY}" = '-security-' ] \
        && [ "${DELAYED_START}" = 'true' ]; then
    for service in support-notifications support-scheduler; do
      sed -n "/^\ \ ${service}:/,/^  [a-z].*:$/p" ${compose}.yml | sed '$d' > tmp/${service}.yml
      sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ SECRETSTORE_RUNTIMETOKENPROVIDER_ENABLED: "true"' tmp/${service}.yml
      sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ SECRETSTORE_RUNTIMETOKENPROVIDER_HOST: edgex-security-spiffe-token-provider' tmp/${service}.yml
      sed -i "s/\/tmp\/edgex\/secrets\/${service}/\/tmp\/edgex\/secrets\/spiffe\/public/g" tmp/${service}.yml
      sed -i "/^\ \ ${service}:/,/^  [a-z].*:$/{//!d}; /^\ \ ${service}:/d" ${compose}.yml
      sed -i "/services:/ r tmp/${service}.yml" ${compose}.yml
    done
  fi

  # Enable North-South Messaging
  if [ "${TEST_STRATEGY}" = "integration-test" ]; then
    sed -n "/^\ \ core-command:/,/^  [a-z].*:$/p" ${compose}.yml | sed '$d' > tmp/core-command.yml
    sed -i '/EXTERNALMQTT_URL/d' tmp/core-command.yml
    sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ EXTERNALMQTT_ENABLED: true' tmp/core-command.yml
    sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ EXTERNALMQTT_URL: tcp:\/\/${EXTERNAL_BROKER_HOSTNAME}:1883' tmp/core-command.yml
    sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ EXTERNALMQTT_RETAIN: false' tmp/core-command.yml
    sed -i "/^\ \ core-command:/,/^  [a-z].*:$/{//!d}; /^\ \ core-command:/d" ${compose}.yml
    sed -i "/services:/ r tmp/core-command.yml" ${compose}.yml
  fi

  # Update app-sample PerTopicPipeline
  sed -n '/^\ \ app-sample:/,/^  [a-z].*:$/p' ${compose}.yml | sed '$d' > tmp/app-sample.yml
  sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ WRITABLE_PIPELINE_FUNCTIONS_HTTPEXPORT_PARAMETERS_URL: http:\/\/${DOCKER_HOST_IP}:7770' tmp/app-sample.yml
  sed -i '/\ \ \ \ environment:/a \ \ \ \ \ \ WRITABLE_PIPELINE_FUNCTIONS_MQTTEXPORT_PARAMETERS_BROKERADDRESS: tcp:\/\/${EXTERNAL_BROKER_HOSTNAME}:1883' tmp/app-sample.yml
  sed -i '$a\ \ \ \ extra_hosts:' tmp/app-sample.yml
  sed -i '$a\ \ \ \ -\ \"${DOCKER_HOST_IP}:host-gateway"' tmp/app-sample.yml
  sed -i '/^\ \ app-sample:/,/^  [a-z].*:$/{//!d}; /^\ \ app-sample:/d' ${compose}.yml
  sed -i '/services:/ r tmp/app-sample.yml' ${compose}.yml

  # Update services which use DOCKER_HOST_IP
  for service in support-notifications app-http-export; do
    sed -n "/^\ \ ${service}:/,/^  [a-z].*:$/p" ${compose}.yml | sed '$d' > tmp/${service}.yml
    sed -i 's/\EXPORT_HOST_PLACE_HOLDER/${DOCKER_HOST_IP}/g' tmp/${service}.yml
    sed -i '$a\ \ \ \ extra_hosts:' tmp/${service}.yml
    sed -i '$a\ \ \ \ -\ \"${DOCKER_HOST_IP}:host-gateway"' tmp/${service}.yml
    sed -i "/^\ \ ${service}:/,/^  [a-z].*:$/{//!d}; /^\ \ ${service}:/d" ${compose}.yml
    sed -i "/services:/ r tmp/${service}.yml" ${compose}.yml
  done

  sed -i '/PROFILE_VOLUME_PLACE_HOLDER: {}/d' ${compose}.yml

  # Update for backward competibility test
  if [ "${USE_SHA1}" = "jakarta" ]; then
    # Supported version:  Ireland, Jakarta, Kamakura
    sed -i 's/\MQTT_BROKER_ADDRESS_PLACE_HOLDER/${EXTERNAL_BROKER_HOSTNAME}/g' ${compose}.yml
  else
    sed -i 's/\MQTT_BROKER_ADDRESS_PLACE_HOLDER/tcp:\/\/${EXTERNAL_BROKER_HOSTNAME}:1883/g' ${compose}.yml
  fi

  sed -i 's/\LOGLEVEL: INFO/LOGLEVEL: DEBUG/g' ${compose}.yml
  sed -i '/METRICSMECHANISM/d' ${compose}.yml  # remove METRICSMECHANISM env variable to allow change on Consul
done
rm -rf tmp
