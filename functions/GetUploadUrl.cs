using Microsoft.AspNetCore.Http;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Azure.WebJobs.Host;
using Microsoft.WindowsAzure.Storage;
using Microsoft.WindowsAzure.Storage.Blob;
using System;
using System.Threading.Tasks;

namespace functions
{
    public static class GetUploadUrl
    {
        [FunctionName("GetUploadUrl")]
        public static async Task<object> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", "options", Route = null)]HttpRequest req, TraceWriter log)
        {
            var filePrefix = "";

            // var userId = req.Headers
            //     .First(q => string.Compare(q.Key, "x-ms-client-principal-id", true) == 0)
            //     .Value
            //     .First();
            // if (string.IsNullOrEmpty(userId)) throw new Exception("No userId");

            // filePrefix = string.IsNullOrEmpty(userId) ? "" : $"{userId}-";

            if (!req.GetQueryParameterDictionary().TryGetValue("filename", out string filenameParameter))
            {
                return new
                {
                    error = "filename parameter is required"
                };
            }

            var filename = filePrefix + filenameParameter;

            CloudStorageAccount storageAccount = CloudStorageAccount.Parse(
                System.Environment.GetEnvironmentVariable("WEBSITE_CONTENTAZUREFILECONNECTIONSTRING", EnvironmentVariableTarget.Process));
            var client = storageAccount.CreateCloudBlobClient();
            var container = client.GetContainerReference("images");
            await container.CreateIfNotExistsAsync();

            CloudBlockBlob blob = container.GetBlockBlobReference($"{filename}");

            SharedAccessBlobPolicy adHocSAS = new SharedAccessBlobPolicy()
            {
                SharedAccessExpiryTime = DateTime.UtcNow.AddMinutes(5),
                Permissions = SharedAccessBlobPermissions.Read | SharedAccessBlobPermissions.Write | SharedAccessBlobPermissions.Create
            };

            var sasBlobToken = blob.GetSharedAccessSignature(adHocSAS);
            return new
            {
                url = blob.Uri + sasBlobToken
            };
        }
    }
}
