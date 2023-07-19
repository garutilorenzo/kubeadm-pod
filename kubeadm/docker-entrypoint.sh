#!/bin/bash

set -eo pipefail
shopt -s nullglob

# check to see if this file is being run or sourced from another script
_is_sourced() {
  # https://unix.stackexchange.com/a/215279
  [ "${#FUNCNAME[@]}" -ge 2 ] \
    && [ "${FUNCNAME[0]}" = '_is_sourced' ] \
    && [ "${FUNCNAME[1]}" = 'source' ]
}

cleanup_oci_secrets(){
  SECRET_ID=$1
  for secret_version_number in $(oci vault secret-version list --secret-id  $SECRET_ID | jq '.data[] | select(.stages[] == "DEPRECATED" and ."time-of-deletion" == null) | ."version-number"')
  do
    echo "Deleting version: $secret_version_number of secret $SECRET_ID"
    TIME_OF_DELETION=$(date -u '+%Y-%m-%dT%H:%M:%SZ' --date="+ 1 day +1 hour")
    oci vault secret-version schedule-deletion --secret-id $SECRET_ID --secret-version-number $secret_version_number --time-of-deletion $TIME_OF_DELETION
  done
}

generate_oci_secrets(){
  HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
  HASH_BASE64=$(echo $HASH | base64 -w0)

  TOKEN=$(kubeadm token create)
  TOKEN_BASE64=$(echo $TOKEN | base64 -w0)

  CERT=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
  CERT_BASE64=$(echo $CERT | base64 -w0)

  hash_ocid=$(oci vault secret list --compartment-id $COMPARTMENT_OCID  | jq -r '.data[] | select(."secret-name" == '"\"$HASH_NAME"\"' and ."lifecycle-state" == "ACTIVE") | .id')
  token_ocid=$(oci vault secret list --compartment-id $COMPARTMENT_OCID | jq -r '.data[] | select(."secret-name" == '"\"$TOKEN_NAME"\"' and ."lifecycle-state" == "ACTIVE") | .id')
  cert_ocid=$(oci vault secret list --compartment-id $COMPARTMENT_OCID  | jq -r '.data[] | select(."secret-name" == '"\"$CERT_NAME"\"' and ."lifecycle-state" == "ACTIVE") | .id')
  
  hash_latest_update_timestamp=$(oci vault secret-version list --secret-id $hash_ocid | jq -r '.data[] | select(.stages[] == "LATEST") | ."time-created"')
  token_latest_update_timestamp=$(oci vault secret-version list --secret-id $token_ocid | jq -r '.data[] | select(.stages[] == "LATEST") | ."time-created"')
  cert_latest_update_timestamp=$(oci vault secret-version list --secret-id $cert_ocid | jq -r '.data[] | select(.stages[] == "LATEST") | ."time-created"')

  hash_latest_update_date=$(date -d $hash_latest_update_timestamp +"%Y%m%d")
  token_latest_update_date=$(date -d $token_latest_update_timestamp +"%Y%m%d")
  cert_latest_update_date=$(date -d $cert_latest_update_timestamp +"%Y%m%d")

  today=$(date +"%Y%m%d")
  if [ $hash_latest_update_date -lt $today ]; then
    oci vault secret update-base64 --secret-id $hash_ocid  --secret-content-content $HASH_BASE64
  else
    echo "Hash already updated on $today"
  fi
  if [ $token_latest_update_date -lt $today ]; then
    oci vault secret update-base64 --secret-id $token_ocid --secret-content-content $TOKEN_BASE64
  else
    echo "Token already updated on $today"
  fi
  if [ $cert_latest_update_date -lt $today ]; then
    oci vault secret update-base64 --secret-id $cert_ocid  --secret-content-content $CERT_BASE64
  else
    echo "Cert already updated on $today"
  fi

  cleanup_oci_secrets $hash_ocid
  cleanup_oci_secrets $token_ocid
  cleanup_oci_secrets $cert_ocid
}

generate_aws_secrets(){
  HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
  echo $HASH > /tmp/ca.txt

  TOKEN=$(kubeadm token create)
  echo $TOKEN > /tmp/kubeadm_token.txt

  CERT=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
  echo $CERT > /tmp/kubeadm_cert.txt
  
  hash_arn=$(aws secretsmanager list-secrets --filter Key="name",Values="$HASH_NAME" | jq -r '.SecretList[0].ARN')
  cert_arn=$(aws secretsmanager list-secrets --filter Key="name",Values="$CERT_NAME" | jq -r '.SecretList[0].ARN')
  token_arn=$(aws secretsmanager list-secrets --filter Key="name",Values="$TOKEN_NAME" | jq -r '.SecretList[0].ARN')

  aws secretsmanager update-secret --secret-id $hash_arn --secret-string file:///tmp/ca.txt
  aws secretsmanager update-secret --secret-id $cert_arn --secret-string file:///tmp/kubeadm_cert.txt
  aws secretsmanager update-secret --secret-id $token_arn --secret-string file:///tmp/kubeadm_token.txt
}

check_vars(){
  PROVIDER=$1
  if [[ $PROVIDER == 'oci' && -z "$COMPARTMENT_OCID" ]]; then
    echo "COMPARTMENT_OCID env variable is required"
    echo "for provider ${PROVIDER}!"
    exit 1
  fi
  if [ -z "$HASH_NAME" ]; then
    echo "HASH_NAME env variable is required!"
    exit 1
  fi
  if [ -z "$CERT_NAME" ]; then
    echo "CERT_NAME env variable is required!"
    exit 1
  fi
  if [ -z "$TOKEN_NAME" ]; then
    echo "TOKEN_NAME env variable is required!"
    exit 1
  fi
}

_main(){
  if [ -z "$PROVIDER" ]; then
    echo "PROVIDER env variable is required!"
    exit 1
  fi

  echo "Running kubeadm-pod for provider ${PROVIDER}..."

  if [ "$1" = 'kubeadm' ]; then
    echo "Generating kubernetes secrets..."
    check_vars $PROVIDER
    if [[ $PROVIDER == 'oci' ]]; then
      export OCI_CLI_AUTH=instance_principal
      generate_oci_secrets
    elif [[  $PROVIDER == 'aws' ]]; then
      generate_aws_secrets
    else
      echo "Provider not supported"
      exit 1
    fi
  fi
  exec "$@"
}

# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
  _main "$@"
fi
