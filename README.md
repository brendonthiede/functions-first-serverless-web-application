# Build your first serverless web app

This fork from https://github.com/Azure-Samples/functions-first-serverless-web-application is intended to be a more opinionated version for use by people with an MSDN Enterprise subscription.  

## Prerequisites

You need to already have an Azure subscription set up and you will need the following software installed:

* [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 2.0 or greater
  * For git-bash I had to set up an alias of `alias az='az.cmd'`, otherwise I had to type `az.cmd` to use the CLI
* Node 10 or greater
* .NET Core 2.0 or greater
* Optional for running functions locally
  * Azure Function Runtime 2.x (`npm install -g azure-functions-core-tools@core`)
  * Azure Storage Emulator (either as part of full [Azure SDK](https://azure.microsoft.com/downloads/) or as a [stand alone](https://go.microsoft.com/fwlink/?linkid=717179&clcid=0x409))

I tried to make everything cross-platform, but it was not to be...  Scripts here are for PowerShell.  I'm moving my notes on how I should have been able to get it working for bash to the bottom section "I Gave Bash on Windows a Shot"

## Tutorial

This is a speed run based on https://docs.microsoft.com/en-us/azure/functions/tutorial-static-website-serverless-api-with-database?tutorial-step=0 with the assumption that you are using an MSDN Enterprise subscription and that you are running commands from bash.  If you are using a different account, just change the name of the subscription from "Visual Studio Enterprise" to the appropriate value.  To get a list of accounts tied to your login, run `az account list`, or to see your current account use `az account show`. If you are using a different cloud than the standard Azure Cloud (e.g. US Government), change the name parameter for the `az cloud set` command.  To get a list of available clouds, run `az cloud list`

Open a bash prompt and change to this directory, then you can start running the following commands:

```powershell
# Connect to your MSDN subscription
az cloud set --name AzureCloud
az login
az account set -s "Visual Studio Enterprise"

# Create infrastructure (adjust location if desired)
$TIMESTAMP = (Get-Date).ToString("yyyyMMdd-HHmm")
$RESOURCE_GROUP_NAME = "first-serverless-app"
$DEPLOYMENT_NAME = "FirstServerlessAppDeployment$TIMESTAMP"
$LOCATION = "eastus"
az group create --name $RESOURCE_GROUP_NAME --location $LOCATION
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
$FUNCTION_STORAGE_BLOB_BASE_URL = ($FUNCTION_STORAGE_BLOB_BASE_URL.Substring(0,$FUNCTION_STORAGE_BLOB_BASE_URL.Length-1))

# Wait for manual steps to be handled through the Azure Portal
echo "Go and enable `"Static website (preview)`" for Function App $FUNCTION_STORAGE_ACCOUNT_NAME before proceeding"
Pause
```

Because some preview features can't be set via ARM template or CLI you need to go to the Azure Portal to enable the "Static website (preview)" feature of the Storage Account.  Log in to the portal and navigate to your Storage Account resource, look for the "Static website (preview)" settings area and click on it.  Click "Enabled" and then enter index.html for the "Index document name" and click "Save".  You should now see the "Primary endpoint", which will be the URL that you'll use to get to the static site.

Now continue with the tutorial to get your static content prepared and uploaded.

```powershell
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
If(Test-path $artifactFolder) { Remove-Item $artifactFolder -Force -Recurse }
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

# Test out the function
Invoke-WebRequest -Uri "$FUNCTION_APP_URL/api/GetUploadUrl?filename=myfile"

# Wait for manual steps to be handled through the Azure Portal
echo "Add the static website URL for Storage Account $FUNCTION_STORAGE_ACCOUNT_NAME to the allowed origins in the CORS configuration for Function App $FUNCTION_APP_NAME before proceeding"
Pause
```

Now you need to configure CORS via the Azure Portal.  Grab the static website URL from the Azure Storage account and add it to the allowed origins for the Function App:

* Find the "Platform Features" for the Function App
* Click the CORS link
* Paste in the static site URL (e.g. https://functutor6sg8lf2ljdyhg.z13.web.core.windows.net) to the allowed origins list
* Click Save

```powershell
# Configure Function App URL and Blob Storage URL for the static app
echo "window.apiBaseUrl = '$FUNCTION_APP_URL'`nwindow.blobBaseUrl = '$FUNCTION_STORAGE_BLOB_BASE_URL'" > www/dist/settings.js
az storage blob upload --container-name `$web --account-name $FUNCTION_STORAGE_ACCOUNT_NAME --file www/dist/settings.js --name settings.js

# Add cosmos DB
$COSMOS_DB_NAME = "azurefunctutdb"
az cosmosdb create --resource-group $RESOURCE_GROUP_NAME --name $COSMOS_DB_NAME
az cosmosdb database create --resource-group $RESOURCE_GROUP_NAME --name $COSMOS_DB_NAME --db-name imagesdb
az cosmosdb collection create --resource-group $RESOURCE_GROUP_NAME --name $COSMOS_DB_NAME --db-name imagesdb --collection-name images --throughput 400

# Add computer vision
$COMPUTER_VISION_ACCOUNT_NAME = "azure-function-tutorial-vision"
az cognitiveservices account create --resource-group $RESOURCE_GROUP_NAME --name $COMPUTER_VISION_ACCOUNT_NAME --kind ComputerVision --sku F0 --location $LOCATION --yes
$COMP_VISION_KEY = (az cognitiveservices account keys list --resource-group $RESOURCE_GROUP_NAME --name $COMPUTER_VISION_ACCOUNT_NAME --query key1 --output tsv)
$COMP_VISION_URL = (az cognitiveservices account show --resource-group $RESOURCE_GROUP_NAME --name $COMPUTER_VISION_ACCOUNT_NAME --query endpoint --output tsv)
az functionapp config appsettings set --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP_NAME --settings COMP_VISION_KEY=$COMP_VISION_KEY COMP_VISION_URL=$COMP_VISION_URL --output table
```

## Quick Snippets

```powershell
# Delete all uploaded images
az storage blob delete-batch -s images --account-name $FUNCTION_STORAGE_ACCOUNT_NAME
az storage blob delete-batch -s thumbnails --account-name $FUNCTION_STORAGE_ACCOUNT_NAME
```

## Creating Functions

The functions that are part of this repo were created as follows via PowerShell (apparently some more Node on Bash on Windows quirks):

```powershell
func init functions
Set-Location functions
func new --language "C#" --template HTTP --AccessRights Anonymous --name GetUploadUrl
```

## I Gave Bash on Windows a Shot

I tried to get everything working from Bash for Windows, but had problems.  I tried git-bash and had different problems.  Here are the notes of what I started doing with bash:

The scripts included here also assume that you have bash installed, i.e. you are running a Mac or Linux or you have Bash on Windows, git-bash, or similar.  I tried using Bash on Windows, but had many issues, so I switched to git-bash.

### Note on Node

While writing this, I was using Bash on Windows, and even though I already had Node installed for Windows, I needed to run the following from the Bash for Windows shell to get npm to work at all for Bash for Windows:

```bash
sudo apt-get --purge remove node
sudo apt-get --purge remove nodejs
sudo apt autoremove node
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt-get install -y gcc g++ make build-essential nodejs
```

This installed a different instance of npm at `/usr/bin/npm`, instead of trying to use `/mnt/c/Program Files/nodejs/npm`.  Installation instructions can be found here: https://github.com/nodesource/distributions#debinstall

I also had to restart Bash for Windows to make sure everything was pointing at the right things.

**HOWEVER**... I still couldn't get the `npm run generate` command to complete in Bash for Windows.  It would just hang with a message of `91% additional chunk assets processing`, even after letting it run for an hour.  I ended up running `npm run generate` from PowerShell and got it to run (although I had to run `npm install -g nuxt` first), taking about 15 seconds.

### Note on git-bash

I ended up trying out git-bash in order to try to make this a more cross-platform README.  I did have to do the following:

#### Setup az Alias

I needed to setup an alias for `az` so that I wouldn't have to type out `az.cmd` which I did with this:

```bash
echo alias az=\'az.cmd\' >> ~/.bashrc
```

#### Install zip Capabilities

I followed instructions here: https://ranxing.wordpress.com/2016/12/13/add-zip-into-git-bash-on-windows/

Which ended up with me unzipping the bin folders of `bzip2-1.0.5-bin.zip` and `zip-3.0-bin.zip` from https://sourceforge.net/projects/gnuwin32/files/ to `C:\Program Files\Git\usr\bin`

Open a bash prompt and change to this directory, then you can start running the following commands:

```bash
# Connect to your MSDN subscription
az cloud set --name AzureCloud
az login
az account set -s "Visual Studio Enterprise"

# Create infrastructure (adjust location if desired)
export TIMESTAMP=$(date '+%Y%m%d-%H%M')
export RESOURCE_GROUP_NAME="first-serverless-app"
export DEPLOYMENT_NAME="FirstServerlessAppDeployment$TIMESTAMP"
az group create --name $RESOURCE_GROUP_NAME --location eastus
export DEPLOYMENT_OUTPUTS=$(az group deployment create \
  --name $DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --template-file ./IAC/autodeploy.json \
  --query 'properties.outputs.[{functionStorageAccountName: functionStorageAccountName.value}]')

# Pull storage name from the deployment output
echo $DEPLOYMENT_OUTPUTS
export FUNCTION_STORAGE_ACCOUNT_NAME=$(echo $DEPLOYMENT_OUTPUTS | awk -F'["]' '{print $4}')

# Wait for manual steps to be handled through the Azure Portal
echo "Go and enable \"Static website (preview)\" for $FUNCTION_STORAGE_ACCOUNT_NAME before proceeding"
read -p "Press [Enter] to continue"
```

Because some preview features can't be set via ARM template or CLI you need to go to the Azure Portal to enable the "Static website (preview)" feature of the Storage Account.  Log in to the portal and navigate to your Storage Account resource, look for the "Static website (preview)" settings area and click on it.  Click "Enabled" and then enter index.html for the "Index document name" and click "Save".  You should now see the "Primary endpoint", which will be the URL that you'll use to get to the static site.

Now continue with the tutorial to get your static content prepared and uploaded.

```bash
# Compile the static site and upload it to storage
cd www
npm install
npm run generate
az storage blob upload-batch --source ./dist --destination \$web --account-name $FUNCTION_STORAGE_ACCOUNT_NAME
```