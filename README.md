# AWS Sentiment Analysis

![End-to-End Sentiment Analysis with AWS](./images/Sentiment%20Analysis%20-%20Title%20Image.png)

This is a simple but otherwise universally usable Proof of Concept [PoC] to showcase how to fully automate Sentiment analysis for customer reviews in AWS with.

In this PoC, S3 is used as data lake, Glue as ETL tool of choice and Comprehend to perform the actual analysis. There are some Lambda functions that are used for cleanup and utility functionality. All these individual resources are stitched together with a Step function that orchestrates the complete sentiment analysis workflow.

Resources are deployed with Terraform. There are no prerequisites required as everything is handled with the Terraform template. This makes it easy to deploy, experiment and destroy when done.

No costs incur for the idle resources except of files in S3.

## How it works

In short, you upload an **unzipped** file with your customer reviews (some **zipped** samples can be found in `./samples` - it is recommended to begin with the smaller data set, which is a subset of the larger data set) to `s3://*sentiment-analysis-data*/input/`.

**Note**: You must not upload multiple files at once. This will trigger multiple executions and is not intended.

The upload triggers the execution of the state machine `*sentiment-analysis` automatically. To start an execution manually with the existing data set, navigate to the state machine `*sentiment-analysis` and start a new execution without any `Input` (it is OK to leave the default `Input`).

Finally, wait until the execution completes (which depends on the amount of data).
The results will be available in `s3://*sentiment-analysis-results*/input/` and include a sentiment for each review.
Retain the results as necessary, as consecutive runs will delete all previous data except of the input data in `s3://*sentiment-analysis-data*/input/`

**Note 1**: Make sure to remove the previous file from `s3://*sentiment-analysis-data*/input/` before uploading any other input data.

**Note 2**: If the input file has a different schema (no columns `id` and `reviews.text`), it is necessary to either adjust the schema before uploading the file to the input bucket, or adjusting the script `src/python/etl-job-scripts/prepare_data.py` (`ChangeSchema` step) and applying the changes using Terraform.

## Workflow

![Workflow](./images/Sentiment%20Analysis%20-%20Workflow.png)

## Architecture

![Architecture](./images/Sentiment%20Analysis%20-%20Architecture.png)
