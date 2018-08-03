# Build your first serverless web app

This fork from https://github.com/Azure-Samples/functions-first-serverless-web-application is intended to be a more opinionated version for use by people with an MSDN Enterprise subscription.  

## Prerequisites

You need to already have an Azure subscription set up and you will need the following software installed:

* [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 2.0 or greater
* Node 10 or greater
* .NET Core 2.0 or greater

The scripts included here also assume that you have bash installed, i.e. you are running a Mac or Linux or you have Bash on Windows, git-bash, or similar.

### Note on Node

While writing this, I was using Bash on Windows, and even though I already had Node installed for Windows, I needed to run the following from the Bash for Windows shell:

```bash
sudo apt-get --purge remove node
sudo apt-get --purge remove nodejs
sudo apt autoremove node
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt-get install -y gcc g++ make build-essential nodejs
```

This installed a different instance of npm at `/usr/bin/npm`, instead of trying to use `/mnt/c/Program Files/nodejs/npm`.  Installation instructions can be found here: https://github.com/nodesource/distributions#debinstall

I also had to restart Bash for Windows to make sure everything was pointing at the right things.

## Tutorial

This is a speed run based on https://docs.microsoft.com/en-us/azure/functions/tutorial-static-website-serverless-api-with-database?tutorial-step=0 with the assumption that you are using an MSDN Enterprise subscription and that you are running commands from bash.  If you are using a different account, just change the name of the subscription from "Visual Studio Enterprise" to the appropriate value.  To get a list of accounts tied to your login, run `az account list`, or to see your current account use `az account show`. If you are using a different cloud than the standard Azure Cloud (e.g. US Government), change the name parameter for the `az cloud set` command.  To get a list of available clouds, run `az cloud list`

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
