import {
  ListObjectsV2Command,
  DeleteObjectsCommand,
  S3Client,
} from "@aws-sdk/client-s3";

const client = new S3Client({});

export const handler = async (event) => {
  console.log(`Bucket: ${event.Bucket}, Prefix: ${event.Prefix}`);

  const listObjectsRequest = new ListObjectsV2Command({
    Bucket: event.Bucket,
    Prefix: event.Prefix ?? "/",
  });

  try {
    let isTruncated = true;
    let objectsToDelete = [];

    while (isTruncated) {
      const { Contents, IsTruncated, NextContinuationToken } =
        await client.send(listObjectsRequest);
      objectsToDelete.push(
        ...Contents.filter((c) => c.Key !== event.Prefix).map((c) => c.Key)
      );
      isTruncated = IsTruncated;
      listObjectsRequest.input.ContinuationToken = NextContinuationToken;
    }

    const numberOfObjectsToDelete = objectsToDelete.length;

    if (numberOfObjectsToDelete > 0) {
      console.log(
        `Your bucket contains the following ${numberOfObjectsToDelete} object${
          numberOfObjectsToDelete === 1 ? "" : "s"
        }:`
      );
      console.log(objectsToDelete.join("\n"));

      let objectsDeleted = [];

      while (objectsToDelete.length > 0) {
        const deleteObjectsRequest = new DeleteObjectsCommand({
          Bucket: event.Bucket,
          Delete: {
            Objects: objectsToDelete.splice(0, 1000).map((o) => {
              return { Key: `${o}` };
            }),
          },
        });
        const { Deleted } = await client.send(deleteObjectsRequest);
        objectsDeleted.push(...Deleted.map((d) => d.Key));
      }

      console.log(
        `Successfully deleted ${
          objectsDeleted.length
        } of ${numberOfObjectsToDelete} object${
          numberOfObjectsToDelete === 1 ? "" : "s"
        } from S3 bucket. Deleted objects:`
      );
      console.log(objectsDeleted.join("\n"));
    } else {
      console.log("No objects to delete");
    }
  } catch (err) {
    console.error(err);
    return {
      statusCode: 500,
      body: JSON.stringify({ Error: err.name, Message: err.message }),
    };
  }

  return {
    statusCode: 200,
    body: JSON.stringify({}),
  };
};
