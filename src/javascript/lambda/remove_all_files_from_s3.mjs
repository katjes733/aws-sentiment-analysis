import {
  ListObjectsV2Command,
  DeleteObjectsCommand,
  S3Client,
} from "@aws-sdk/client-s3";

const client = new S3Client({});

export const handler = async (event) => {
  const bucket = event.Bucket;
  const prefix = event.Prefix;
  const skipKeys = event.SkipKeys?.filter((k) => k.trim()) ?? [];
  const skipIfNoSkipKeys =
    event.SkipIfNoSkipKeys?.toLowerCase() === "true" ? true : false;

  console.log(
    `Bucket: ${bucket}, Prefix: ${prefix}, SkipKeys: ${skipKeys}, SkipIfNoSkipKeys: ${skipIfNoSkipKeys}`
  );

  if (skipKeys.length === 0 && skipIfNoSkipKeys) {
    return {
      ObjectsDeleted: [],
    };
  }

  const listObjectsRequest = new ListObjectsV2Command({
    Bucket: bucket,
    Prefix: prefix ?? "/",
  });

  try {
    let isTruncated = true;
    let objectsToDelete = [];

    while (isTruncated) {
      const { Contents, IsTruncated, NextContinuationToken } =
        await client.send(listObjectsRequest);
      objectsToDelete.push(
        ...Contents.filter(
          (c) => c.Key !== prefix && !skipKeys.includes(c.Key)
        ).map((c) => c.Key)
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
          Bucket: bucket,
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

      return {
        ObjectsDeleted: objectsDeleted,
      };
    } else {
      console.log("No objects to delete");

      return {
        ObjectsDeleted: [],
      };
    }
  } catch (err) {
    console.error(err);
    return {
      statusCode: 500,
      body: JSON.stringify({ Error: err.name, Message: err.message }),
    };
  }
};
