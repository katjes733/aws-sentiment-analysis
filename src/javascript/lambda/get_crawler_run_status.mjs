import { GlueClient, GetCrawlerCommand } from "@aws-sdk/client-glue";

const client = new GlueClient({});

export const handler = async (event) => {
  console.log(`Crawler Name: ${event.CrawlerName}`);

  const input = {
    Name: event.CrawlerName,
  };
  const command = new GetCrawlerCommand(input);

  const response = await client.send(command);
  let status = "RUNNING";
  if (response.Crawler.State === "READY") {
    status = response.Crawler.LastCrawl.Status;
  }

  return {
    CrawlStatus: status,
    CrawlerName: event.CrawlerName,
  };
};
