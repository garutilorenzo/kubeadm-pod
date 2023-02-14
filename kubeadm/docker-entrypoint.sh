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
  
  oci vault secret update-base64 --secret-id $hash_ocid  --secret-content-content $HASH_BASE64
  oci vault secret update-base64 --secret-id $token_ocid --secret-content-content $TOKEN_BASE64
  oci vault secret update-base64 --secret-id $cert_ocid  --secret-content-content $CERT_BASE64
}

generate_aws_secrets(){
  wait_for_secretsmanager
  HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
  echo $HASH > /tmp/ca.txt

  TOKEN=$(kubeadm token create)
  echo $TOKEN > /tmp/kubeadm_token.txt

  CERT=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
  echo $CERT > /tmp/kubeadm_cert.txt

  aws secretsmanager update-secret --secret-id $HASH_NAME --secret-string file:///tmp/ca.txt
  aws secretsmanager update-secret --secret-id $CERT_NAME --secret-string file:///tmp/kubeadm_cert.txt
  aws secretsmanager update-secret --secret-id $TOKEN_NAME --secret-string file:///tmp/kubeadm_token.txt
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
