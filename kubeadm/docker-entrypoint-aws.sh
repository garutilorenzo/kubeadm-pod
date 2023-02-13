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

generate_secrets(){
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
  if [ "$1" = 'kubeadm' ]; then
    while :
    do
      echo "Generating kubernetes secrets..."
      check_vars
      generate_secrets
      sleep 3600
    done
  fi
  exec "$@"
}

# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
  _main "$@"
fi
