using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Host;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using SixLabors.Primitives;
using System;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;

namespace functions
{
    public static class ResizeImage
    {
        private static HttpClient httpClient = new HttpClient();

        [FunctionName("ResizeImage")]
        public static async void Run([BlobTrigger("images/{name}",
            Connection = "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING")]Stream myBlob,
            string name,
            [Blob("thumbnails/{name}", FileAccess.Write)]Stream thumbnail,
            [CosmosDB(
                databaseName: "imagesdb",
                collectionName: "images",
                ConnectionStringSetting = "CosmosDBConnection")]IAsyncCollector<ImageInfo> documents,
            TraceWriter log)
        {
            const int SIZE = 200;
            const int QUALITY = 75;

            using (Image<Rgba32> image = Image.Load(myBlob))
            {
                image.Mutate(x => x
                     .Resize(new ResizeOptions
                     {
                         Size = new Size(SIZE, SIZE),
                         Mode = ResizeMode.Max
                     }));
                image.SaveAsJpeg(thumbnail, new SixLabors.ImageSharp.Formats.Jpeg.JpegEncoder
                {
                    IgnoreMetadata = false,
                    Quality = QUALITY
                });
            }

            var request = new HttpRequestMessage()
            {
                RequestUri = new Uri(Environment.GetEnvironmentVariable("COMP_VISION_URL", EnvironmentVariableTarget.Process) + "/analyze?visualFeatures=Description&amp;language=en"),
                Method = HttpMethod.Post,
                Content = new StreamContent(myBlob)
            };
            request.Headers.Add(
                "Ocp-Apim-Subscription-Key",
                Environment.GetEnvironmentVariable("COMP_VISION_KEY", EnvironmentVariableTarget.Process));
            request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");

            var response = await httpClient.SendAsync(request);
            dynamic result = await response.Content.ReadAsAsync<object>();

            await documents.AddAsync(new ImageInfo
            {
                id = name,
                imgPath = "/images/" + name,
                thumbnailPath = "/thumbnails/" + name,
                description = result.description
            });
        }
    }
}
