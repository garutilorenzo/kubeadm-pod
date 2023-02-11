
#!/bin/bash

generate_vault_secrets(){
  HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
  HASH_BASE64=$(echo $HASH | base64 -w0)

  TOKEN=$(kubeadm token create)
  TOKEN_BASE64=$(echo $TOKEN | base64 -w0)

  CERT=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
  CERT_BASE64=$(echo $CERT | base64 -w0)

  hash_ocid=$(oci vault secret list --compartment-id $COMPARTMENT_OCID  | jq -r '.data[] | select(."secret-name" == "${hash_secret_name}-${environment}" and ."lifecycle-state" == "ACTIVE") | .id')
  token_ocid=$(oci vault secret list --compartment-id $COMPARTMENT_OCID | jq -r '.data[] | select(."secret-name" == "${token_secret_name}-${environment}" and ."lifecycle-state" == "ACTIVE") | .id')
  cert_ocid=$(oci vault secret list --compartment-id $COMPARTMENT_OCID  | jq -r '.data[] | select(."secret-name" == "${cert_secret_name}-${environment}" and ."lifecycle-state" == "ACTIVE") | .id')
  
  oci vault secret update-base64 --secret-id $HASH_OCID  --secret-content-content $HASH_BASE64
  oci vault secret update-base64 --secret-id $TOKEN_OCID --secret-content-content $TOKEN_BASE64
  oci vault secret update-base64 --secret-id $CERT_OCID  --secret-content-content $CERT_BASE64
}

check_vars(){
  if [ -z "$COMPARTMENT_OCID" ]; then
    echo "COMPARTMENT_OCID env variable is required!"
    exit 1
  fi
  if [ -z "$HASH_OCID" ]; then
    echo "HASH_OCID env variable is required!"
    exit 1
  fi
  if [ -z "$TOKEN_OCID" ]; then
    echo "TOKEN_OCID env variable is required!"
    exit 1
  fi
  if [ -z "$CERT_OCID" ]; then
    echo "CERT_OCID env variable is required!"
    exit 1
  fi
}

export OCI_CLI_AUTH=instance_principal
check_vars

if [ "$1" = 'kubeadm' ]; then
  while :
  do
    echo "Generating kubernetes secrets..."
    generate_vault_secrets
    sleep 3600
  done
fi
exec "$@"