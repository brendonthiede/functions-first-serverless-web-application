using Microsoft.AspNetCore.Http;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Azure.WebJobs.Host;
using System.Collections.Generic;

namespace functions
{
    public static class GetImages
    {
        [FunctionName("GetImages")]
        public static IEnumerable<ImageInfo> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", "options", Route = null)]HttpRequest req,
            [CosmosDB(
                databaseName: "imagesdb",
                collectionName: "images",
                ConnectionStringSetting = "CosmosDBConnection",
                SqlQuery = "select * from c order by c._ts desc")]IEnumerable<ImageInfo> documents,
            TraceWriter log)
        {
            return documents;
        }
    }
}
