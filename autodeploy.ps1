param(
  [Parameter(Mandatory = $False)]
  [String]
  $EnvironmentName = "AzureCloud",

  [Parameter(Mandatory = $False)]
  [String]
  $SubscriptioName = "Visual Studio Enterprise",

  [Parameter(Mandatory = $False)]
  [String]
  $ResourceLocation = "eastus"
)

# Login to Azure
$FOREGROUND_COLOR = ([console]::ForegroundColor)
$BACKGROUND_COLOR = ([console]::BackgroundColor)
$ACCOUNT_INFO = (az account show | ConvertFrom-Json)
[console]::ForegroundColor = $FOREGROUND_COLOR
[console]::BackgroundColor = $BACKGROUND_COLOR
if ($ACCOUNT_INFO.environmentName -ne "$EnvironmentName" -or $ACCOUNT_INFO.name -ne "$SubscriptioName") {
  az cloud set --name "$EnvironmentName"
  az login
  az account set --subscription "$SubscriptioName"
}

# Create infrastructure (adjust location if desired)
$TIMESTAMP = (Get-Date).ToString("yyyyMMdd-HHmm")
$RESOURCE_GROUP_NAME = "first-serverless-app"
$DEPLOYMENT_NAME = "FirstServerlessAppDeployment$TIMESTAMP"
az group create --name $RESOURCE_GROUP_NAME --location $ResourceLocation --tag purpose=tutorial
$DEPLOYMENT_OUTPUTS = (az group deployment create `
    --name $DEPLOYMENT_NAME `
    --resource-group $RESOURCE_GROUP_NAME `
    --template-file ./autodeploy.json)

# Pull deployment output into variables
$DEPLOYMENT_OUTPUTS = ($DEPLOYMENT_OUTPUTS | ConvertFrom-Json).properties.outputs
$FUNCTION_APP_NAME = $DEPLOYMENT_OUTPUTS.functionAppName.value
$FUNCTION_STORAGE_ACCOUNT_NAME = $DEPLOYMENT_OUTPUTS.functionStorageAccountName.value
$FUNCTION_APP_URI = $DEPLOYMENT_OUTPUTS.functionAppUri.value
$FUNCTION_APP_URL = "https://$FUNCTION_APP_URI"
$FUNCTION_STORAGE_BLOB_BASE_URL = $DEPLOYMENT_OUTPUTS.functionStorageBlobBaseUrl.value
$FUNCTION_STORAGE_BLOB_BASE_URL = ($FUNCTION_STORAGE_BLOB_BASE_URL.Substring(0, $FUNCTION_STORAGE_BLOB_BASE_URL.Length - 1))
$COSMOS_DB_ACCOUNT_NAME = $DEPLOYMENT_OUTPUTS.cosmosDbAccountName.value

# Wait for manual steps to be handled through the Azure Portal
echo "Go and enable `"Static website (preview)`" for Function App $FUNCTION_STORAGE_ACCOUNT_NAME before proceeding"
Pause

echo "Add the static website URL for Storage Account $FUNCTION_STORAGE_ACCOUNT_NAME to the allowed origins in the CORS configuration for Function App $FUNCTION_APP_NAME before proceeding"
Pause

# Compile the static site
cd www
npm install
npm run generate
cd ..

# Upload to static site storage
az storage blob upload-batch --source ./www/dist --destination `$web --account-name $FUNCTION_STORAGE_ACCOUNT_NAME

# Create storage container for images
az storage container create -n images --account-name $FUNCTION_STORAGE_ACCOUNT_NAME --public-access blob
az storage container create -n thumbnails --account-name $FUNCTION_STORAGE_ACCOUNT_NAME --public-access blob

# Configure CORS settings to allow any origin
az storage cors add --methods OPTIONS PUT --origins '*' --exposed-headers '*' --allowed-headers '*' --services b --account-name $FUNCTION_STORAGE_ACCOUNT_NAME

# Compile Azure functions and package them for deployment
cd functions
$artifactFolder = "$($PWD.Path)/dist"
$publishOut = "$artifactFolder/artifact"
If (Test-path $artifactFolder) { Remove-Item $artifactFolder -Force -Recurse }
dotnet publish functions.csproj --configuration Debug --output $publishOut
Add-Type -assembly "system.io.compression.filesystem"
[io.compression.zipfile]::CreateFromDirectory($publishOut, "$artifactFolder\functions.zip")
Remove-Item $publishOut -Force -Recurse
cd ..

# Deploy function to Azure
az functionapp deployment source config-zip `
  --resource-group $RESOURCE_GROUP_NAME `
  --name $FUNCTION_APP_NAME `
  --src ".\functions\dist\functions.zip"

# Configure Function App URL and Blob Storage URL for the static app
echo "window.apiBaseUrl = '$FUNCTION_APP_URL'`nwindow.blobBaseUrl = '$FUNCTION_STORAGE_BLOB_BASE_URL'" > www/dist/settings.js
az storage blob upload --container-name `$web --account-name $FUNCTION_STORAGE_ACCOUNT_NAME --file www/dist/settings.js --name settings.js

# Create Cosmos DB database and collection for storing image information
if (!(az cosmosdb database exists --resource-group $RESOURCE_GROUP_NAME --name $COSMOS_DB_ACCOUNT_NAME --db-name imagesdb)) {
  az cosmosdb database create --resource-group $RESOURCE_GROUP_NAME --name $COSMOS_DB_ACCOUNT_NAME --db-name imagesdb
}
if (!(az cosmosdb collection exists --resource-group $RESOURCE_GROUP_NAME --name $COSMOS_DB_ACCOUNT_NAME --db-name imagesdb --collection-name images)) {
  az cosmosdb collection create --resource-group $RESOURCE_GROUP_NAME --name $COSMOS_DB_ACCOUNT_NAME --db-name imagesdb --collection-name images --throughput 400
}
