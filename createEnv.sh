. ./properties

# Create Resource Group, Cluster and KeyVault
az group create -n $RG -l $LOCATION
az aks create -n $CLUSTER1NAME -g $RG --enable-addons azure-keyvault-secrets-provider --node-count 1 -l $LOCATION
az keyvault create -n $KEYVAULT -g $RG -l $LOCATION
az aks get-credentials -n $CLUSTER1NAME -g $RG

# Get Cluster's ID
CLUSTERID=$(az aks show -g $RG -n $CLUSTER1NAME --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)

# Set Permissions on Cluster's ID
az keyvault set-policy -n $KEYVAULT --key-permissions get --spn $CLUSTERID
az keyvault set-policy -n $KEYVAULT --certificate-permissions get --spn $CLUSTERID
az keyvault set-policy -n $KEYVAULT --secret-permissions get --spn $CLUSTERID

# Get vnet name and set restrictions on keyvault
NRG=$(az aks show -g $RG -n $CLUSTER1NAME --query nodeResourceGroup -o tsv)
VNET=$(az network vnet list -g $NRG --query [*].name -o tsv)
SUBNET=$(az network vnet subnet list -g $NRG --vnet-name $VNET --query [*].name -o tsv)
SUBNETID=$(az network vnet subnet list -g $NRG --vnet-name $VNET --query [*].id -o tsv)
MYIP=$(curl ifconfig.co)

az network vnet subnet update --resource-group $NRG --vnet-name $VNET --name $SUBNET --service-endpoints "Microsoft.KeyVault"
az keyvault network-rule add --resource-group $RG --name $KEYVAULT --subnet $SUBNETID
az keyvault network-rule add --resource-group $RG --name $KEYVAULT --ip-address "${MYIP}"

az keyvault update --resource-group $RG --name $KEYVAULT --default-action Deny
az keyvault secret set --vault-name $KEYVAULT -n ExampleSecret --value MyAKSExampleSecret
az keyvault network-rule remove --resource-group $RG --name $KEYVAULT --ip-address "${MYIP}/32"

TENANTID=$(az account show --query tenantId -o tsv)

cat << EOF | kubectl apply -f -
# This is a SecretProviderClass example using user-assigned identity to access your key vault
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: secretprovider1
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"          # Set to true for using managed identity
    userAssignedIdentityID: $CLUSTERID   # Set the clientID of the user-assigned managed identity to use
    keyvaultName: $KEYVAULT        # Set to the name of your key vault
    cloudName: ""                         # [OPTIONAL for Azure] if not provided, the Azure environment defaults to AzurePublicCloud
    objects:  |
      array:
        - |
          objectName: ExampleSecret
          objectType: secret              # object types: secret, key, or cert
          objectVersion: ""               # [OPTIONAL] object versions, default to latest if empty
    tenantId: $TENANTID                 # The tenant ID of the key vault
EOF


cat << EOF | kubectl apply -f -
# This is a sample pod definition for using SecretProviderClass and the user-assigned identity to access your key vault
kind: Pod
apiVersion: v1
metadata:
  name: secretpod
spec:
  containers:
    - name: secretpod
      image: k8s.gcr.io/e2e-test-images/busybox:1.29-1
      command:
        - "/bin/sleep"
        - "10000"
      volumeMounts:
      - name: secretmount
        mountPath: "/mnt/secrets-store"
        readOnly: true
  volumes:
    - name: secretmount
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "secretprovider1"
EOF

az aks create -n $CLUSTER2NAME -g $RG --enable-addons azure-keyvault-secrets-provider --node-count 1 -l $LOCATION

CLUSTERID=$(az aks show -g $RG -n $CLUSTER2NAME --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)
az aks get-credentials -n $CLUSTER2NAME -g $RG

cat << EOF | kubectl apply -f -
# This is a SecretProviderClass example using user-assigned identity to access your key vault
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: secretprovider1
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"          # Set to true for using managed identity
    userAssignedIdentityID: $CLUSTERID   # Set the clientID of the user-assigned managed identity to use
    keyvaultName: $KEYVAULT        # Set to the name of your key vault
    cloudName: ""                         # [OPTIONAL for Azure] if not provided, the Azure environment defaults to AzurePublicCloud
    objects:  |
      array:
        - |
          objectName: ExampleSecret
          objectType: secret              # object types: secret, key, or cert
          objectVersion: ""               # [OPTIONAL] object versions, default to latest if empty
    tenantId: $TENANTID                 # The tenant ID of the key vault
EOF


cat << EOF | kubectl apply -f -
# This is a sample pod definition for using SecretProviderClass and the user-assigned identity to access your key vault
kind: Pod
apiVersion: v1
metadata:
  name: secretpod
spec:
  containers:
    - name: secretpod
      image: k8s.gcr.io/e2e-test-images/busybox:1.29-1
      command:
        - "/bin/sleep"
        - "10000"
      volumeMounts:
      - name: secretmount
        mountPath: "/mnt/secrets-store"
        readOnly: true
  volumes:
    - name: secretmount
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "secretprovider1"
EOF
