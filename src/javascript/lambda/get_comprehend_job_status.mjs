import {
  ComprehendClient,
  DescribeSentimentDetectionJobCommand,
} from "@aws-sdk/client-comprehend";

const client = new ComprehendClient({});

export const handler = async (event) => {
  console.log(`JobId: ${event.JobId}`);

  const input = {
    JobId: event.JobId,
  };
  const command = new DescribeSentimentDetectionJobCommand(input);

  const response = await client.send(command);
  console.log(
    `JobStatus: ${response.SentimentDetectionJobProperties.JobStatus}`
  );
  return {
    JobStatus: response.SentimentDetectionJobProperties.JobStatus,
    JobId: event.JobId,
  };
};
