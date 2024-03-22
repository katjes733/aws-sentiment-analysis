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
    format_options={"multiline": False},
    connection_type="s3",
    format="json",
    connection_options={
        "paths": [
            f's3://{args["BUCKET"]}/analyzed/'
        ],
        "recurse": True,
    },
    transformation_ctx="AmazonS3_node1710787517038",
)

# Script generated for node Change Schema
ChangeSchema_node1710862366049 = ApplyMapping.apply(
    frame=AmazonS3_node1710787517038,
    mappings=[
        ("file", "string", "file", "string"),
        ("line", "int", "line", "int"),
        ("sentiment", "string", "sentiment", "string"),
        ("sentimentscore.mixed", "double", ".mixed", "double"),
        ("sentimentscore.negative", "double", ".negative", "double"),
        ("sentimentscore.neutral", "double", ".neutral", "double"),
        ("sentimentscore.positive", "double", ".positive", "double"),
    ],
    transformation_ctx="ChangeSchema_node1710862366049",
)

# Script generated for node Amazon S3
AmazonS3_node1710787564323 = glueContext.write_dynamic_frame.from_options(
    frame=ChangeSchema_node1710862366049,
    connection_type="s3",
    format="csv",
    connection_options={
        "path": f's3://{args["BUCKET"]}/results/',
        "compression": "gzip",
        "partitionKeys": [],
    },
    transformation_ctx="AmazonS3_node1710787564323",
)

job.commit()
