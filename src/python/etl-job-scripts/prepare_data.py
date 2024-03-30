import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ["JOB_NAME", "BUCKET"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# Script generated for node Amazon S3
AmazonS3_node1710787517038 = glueContext.create_dynamic_frame.from_options(
    format_options={
        "quoteChar": '"',
        "withHeader": True,
        "separator": ",",
        "optimizePerformance": False,
    },
    connection_type="s3",
    format="csv",
    connection_options={
        "paths": [
            f's3://{args["BUCKET"]}/input/'
        ]
    },
    transformation_ctx="AmazonS3_node1710787517038",
)

# Script generated for node Change Schema
ChangeSchema_node1710787555053 = ApplyMapping.apply(
    frame=AmazonS3_node1710787517038,
    mappings=[
        ("id", "string", "id", "string"),
        ("`reviews.text`", "string", "review", "string"),
    ],
    transformation_ctx="ChangeSchema_node1710787555053",
)

# Script generated for node Amazon S3
AmazonS3_node1710787564323 = glueContext.write_dynamic_frame.from_options(
    frame=ChangeSchema_node1710787555053,
    connection_type="s3",
    format="csv",
    format_options={
        "writeHeader": False,
    },
    connection_options={
        "path": f's3://{args["BUCKET"]}/prepared/',
        "partitionKeys": ["id"],
    },
    transformation_ctx="AmazonS3_node1710787564323",
)

job.commit()
