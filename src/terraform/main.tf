data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_iam_role" "quicksight_service_role" {
  name = "aws-quicksight-service-role-v0"
}

data "aws_iam_policy" "quicksight_athena_policy" {
  name = "AWSQuicksightAthenaAccess"
}

locals {
  resource_prefix = "%{if var.resource_prefix != ""}${var.resource_prefix}%{else}${random_string.unique_id}-%{endif}"
}

locals {
  is_arm_supported_region                          = contains(["us-east-1", "us-west-2", "eu-central-1", "eu-west-1", "ap-south-1", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1"], data.aws_region.current.name)
  etl_job_script_prepare_data_source_name          = "${path.module}/../python/etl-job-scripts/prepare_data.py"
  etl_job_script_prepare_results_source_name       = "${path.module}/../python/etl-job-scripts/prepare_results.py"
  unzip_files_lambda_function_name                 = "${local.resource_prefix}unzip-files"
  remove_all_files_from_s3_lambda_function_name    = "${local.resource_prefix}remove-all-files-from-s3"
  get_comprehend_job_status_lambda_function_name   = "${local.resource_prefix}get-comprehend-job-status"
  get_crawler_run_status_lambda_function_name      = "${local.resource_prefix}get-crawler-run-status"
  sentiment_analysis_prepare_data_glue_job_name    = "${local.resource_prefix}sentiment-analysis-prepare-data"
  sentiment_analysis_prepare_results_glue_job_name = "${local.resource_prefix}sentiment-analysis-prepare-results"
  sentiment_analysis_state_machine_name            = "${local.resource_prefix}sentiment-analysis"
}

resource "random_string" "unique_id" {
  count   = var.resource_prefix == "" ? 1 : 0
  length  = 8
  special = false
}

resource "aws_s3_bucket" "sentiment_analysis_assets_bucket" {
  bucket        = "${local.resource_prefix}sentiment-analysis-assets-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sentiment_analysis_assets_bucket_sse" {
  bucket = aws_s3_bucket.sentiment_analysis_assets_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "sentiment_analysis_assets_bucket_block" {
  bucket                  = aws_s3_bucket.sentiment_analysis_assets_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "etl_job_script_prepare_data" {
  key                    = "prepare_data.py"
  bucket                 = aws_s3_bucket.sentiment_analysis_assets_bucket.id
  source                 = local.etl_job_script_prepare_data_source_name
  source_hash            = filemd5(local.etl_job_script_prepare_data_source_name)
  server_side_encryption = "AES256"
}

resource "aws_s3_object" "etl_job_script_prepare_results" {
  key                    = "prepare_results.py"
  bucket                 = aws_s3_bucket.sentiment_analysis_assets_bucket.id
  source                 = local.etl_job_script_prepare_results_source_name
  source_hash            = filemd5(local.etl_job_script_prepare_results_source_name)
  server_side_encryption = "AES256"
}

resource "aws_s3_bucket" "sentiment_analysis_data_bucket" {
  bucket        = "${local.resource_prefix}sentiment-analysis-data-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sentiment_analysis_data_bucket_sse" {
  bucket = aws_s3_bucket.sentiment_analysis_data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "sentiment_analysis_data_bucket_block" {
  bucket                  = aws_s3_bucket.sentiment_analysis_data_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "sentiment_analysis_data_bucket_notification" {
  bucket      = aws_s3_bucket.sentiment_analysis_data_bucket.id
  eventbridge = true
}

resource "aws_s3_object" "folder_input" {
  key          = "input/"
  bucket       = aws_s3_bucket.sentiment_analysis_data_bucket.id
  content_type = "application/x-directory"
}

resource "aws_s3_object" "folder_prepared" {
  key          = "prepared/"
  bucket       = aws_s3_bucket.sentiment_analysis_data_bucket.id
  content_type = "application/x-directory"
}

resource "aws_s3_object" "folder_analyzed" {
  key          = "analyzed/"
  bucket       = aws_s3_bucket.sentiment_analysis_data_bucket.id
  content_type = "application/x-directory"
}

resource "aws_s3_object" "folder_results" {
  key          = "results/"
  bucket       = aws_s3_bucket.sentiment_analysis_data_bucket.id
  content_type = "application/x-directory"
}

resource "aws_s3_bucket" "sentiment_analysis_temp_data_bucket" {
  bucket        = "${local.resource_prefix}sentiment-analysis-temp-data-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sentiment_analysis_temp_data_bucket_sse" {
  bucket = aws_s3_bucket.sentiment_analysis_temp_data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "sentiment_analysis_temp_data_bucket_block" {
  bucket                  = aws_s3_bucket.sentiment_analysis_temp_data_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "folder_athena_query_results" {
  key          = "athena/query-results/"
  bucket       = aws_s3_bucket.sentiment_analysis_temp_data_bucket.id
  content_type = "application/x-directory"
}

# ##################################################################################################
# Resources for unzip files lambda function
# ##################################################################################################

resource "aws_iam_role" "unzip_files_lambda_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}unzip-files-lambda-role" : null
  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    aws_iam_policy.unzip_files_lambda_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "unzip_files_lambda_role_policy" {
  name = "${local.resource_prefix}unzip-files-lambda-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}",
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}/*"
        ]
      },
      {
        Action = ["s3:List*"]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}",
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}/*"
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "unzip_files_lambda_log_group" {
  name              = "/aws/lambda/${local.unzip_files_lambda_function_name}"
  retention_in_days = 7
}

data "archive_file" "unzip_files_package" {
  type        = "zip"
  source_file = "${path.module}/../python/lambda/unzip_files.py"
  output_path = "${path.module}/.package/unzip_files.zip"
}

resource "aws_lambda_function" "unzip_files_lambda" {
  depends_on = [
    aws_cloudwatch_log_group.unzip_files_lambda_log_group
  ]
  function_name    = local.unzip_files_lambda_function_name
  architectures    = local.is_arm_supported_region ? ["arm64"] : ["x86_64"]
  filename         = "${path.module}/.package/unzip_files.zip"
  source_code_hash = data.archive_file.unzip_files_package.output_base64sha256
  handler          = "unzip_files.lambda_handler"
  runtime          = "python3.12"
  memory_size      = 256
  timeout          = 900
  role             = aws_iam_role.unzip_files_lambda_role.arn
  environment {
    variables = {
      "LOG_LEVEL" = "info"
    }
  }
}

# ##################################################################################################
# Resources for remove all files from S3 lambda function
# ##################################################################################################

resource "aws_iam_role" "remove_all_files_from_s3_lambda_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}remove-all-files-from-s3-lambda-role" : null
  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    aws_iam_policy.remove_all_files_from_s3_lambda_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "remove_all_files_from_s3_lambda_role_policy" {
  name = "${local.resource_prefix}remove-all-files-from-s3-lambda-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:Get*",
          "s3:List*",
          "s3:Delete*"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}",
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}/*"
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "remove_all_files_from_s3_lambda_log_group" {
  name              = "/aws/lambda/${local.remove_all_files_from_s3_lambda_function_name}"
  retention_in_days = 7
}

data "archive_file" "remove_all_files_from_s3_package" {
  type        = "zip"
  source_file = "${path.module}/../javascript/lambda/remove_all_files_from_s3.mjs"
  output_path = "${path.module}/.package/remove_all_files_from_s3.zip"
}

resource "aws_lambda_function" "remove_all_files_from_s3_lambda" {
  depends_on = [
    aws_cloudwatch_log_group.remove_all_files_from_s3_lambda_log_group
  ]
  function_name    = local.remove_all_files_from_s3_lambda_function_name
  architectures    = local.is_arm_supported_region ? ["arm64"] : ["x86_64"]
  filename         = "${path.module}/.package/remove_all_files_from_s3.zip"
  source_code_hash = data.archive_file.remove_all_files_from_s3_package.output_base64sha256
  handler          = "remove_all_files_from_s3.handler"
  runtime          = "nodejs20.x"
  memory_size      = 128
  timeout          = 300
  role             = aws_iam_role.remove_all_files_from_s3_lambda_role.arn
}

# ##################################################################################################
# Resources for get comprehend job status lambda function
# ##################################################################################################

resource "aws_iam_role" "get_comprehend_job_status_lambda_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}get-comprehend-job-status-lambda-role" : null
  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    aws_iam_policy.get_comprehend_job_status_lambda_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "get_comprehend_job_status_lambda_role_policy" {
  name = "${local.resource_prefix}get-comprehend-job-status-lambda-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "comprehend:DescribeSentimentDetectionJob"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:comprehend:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:sentiment-detection-job/*"
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "get_comprehend_job_status_lambda_log_group" {
  name              = "/aws/lambda/${local.get_comprehend_job_status_lambda_function_name}"
  retention_in_days = 7
}

data "archive_file" "get_comprehend_job_status_package" {
  type        = "zip"
  source_file = "${path.module}/../javascript/lambda/get_comprehend_job_status.mjs"
  output_path = "${path.module}/.package/get_comprehend_job_status.zip"
}

resource "aws_lambda_function" "get_comprehend_job_status_lambda" {
  depends_on = [
    aws_cloudwatch_log_group.get_comprehend_job_status_lambda_log_group
  ]
  function_name    = local.get_comprehend_job_status_lambda_function_name
  architectures    = local.is_arm_supported_region ? ["arm64"] : ["x86_64"]
  filename         = "${path.module}/.package/get_comprehend_job_status.zip"
  source_code_hash = data.archive_file.get_comprehend_job_status_package.output_base64sha256
  handler          = "get_comprehend_job_status.handler"
  runtime          = "nodejs20.x"
  memory_size      = 128
  timeout          = 60
  role             = aws_iam_role.get_comprehend_job_status_lambda_role.arn
}

# ##################################################################################################
# Resources for get crawler run status lambda function
# ##################################################################################################

resource "aws_iam_role" "get_crawler_run_status_lambda_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}get-crawler-run-status-lambda-role" : null
  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    aws_iam_policy.get_crawler_run_status_lambda_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "get_crawler_run_status_lambda_role_policy" {
  name = "${local.resource_prefix}get-crawler-run-status-lambda-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "glue:GetCrawler"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:crawler/*"
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "get_crawler_run_status_lambda_log_group" {
  name              = "/aws/lambda/${local.get_crawler_run_status_lambda_function_name}"
  retention_in_days = 7
}

data "archive_file" "get_crawler_run_status_package" {
  type        = "zip"
  source_file = "${path.module}/../javascript/lambda/get_crawler_run_status.mjs"
  output_path = "${path.module}/.package/get_crawler_run_status.zip"
}

resource "aws_lambda_function" "get_crawler_run_status_lambda" {
  depends_on = [
    aws_cloudwatch_log_group.get_crawler_run_status_lambda_log_group
  ]
  function_name    = local.get_crawler_run_status_lambda_function_name
  architectures    = local.is_arm_supported_region ? ["arm64"] : ["x86_64"]
  filename         = "${path.module}/.package/get_crawler_run_status.zip"
  source_code_hash = data.archive_file.get_crawler_run_status_package.output_base64sha256
  handler          = "get_crawler_run_status.handler"
  runtime          = "nodejs20.x"
  memory_size      = 128
  timeout          = 60
  role             = aws_iam_role.get_crawler_run_status_lambda_role.arn
}

# ##################################################################################################
# Common resources for Glue
# ##################################################################################################

resource "aws_iam_role" "sentiment_analysis_glue_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}sentiment-analysis-glue-role" : null
  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole",
    aws_iam_policy.sentiment_analysis_glue_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "sentiment_analysis_glue_role_policy" {
  name = "${local.resource_prefix}sentiment-analysis-glue-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}/*",
          "${aws_s3_bucket.sentiment_analysis_assets_bucket.arn}/*"
        ]
      },
    ]
  })
}

# ##################################################################################################
# Resources for Glue Job to prepare data
# ##################################################################################################

resource "aws_cloudwatch_log_group" "sentiment_analysis_prepare_data_glue_job_log_group" {
  name              = "/aws/lambda/${local.sentiment_analysis_prepare_data_glue_job_name}"
  retention_in_days = 7
}

resource "aws_glue_job" "sentiment_analysis_prepare_data_glue_job" {
  name     = local.sentiment_analysis_prepare_data_glue_job_name
  role_arn = aws_iam_role.sentiment_analysis_glue_role.arn

  glue_version      = "4.0"
  number_of_workers = 10
  worker_type       = "G.1X"

  default_arguments = {
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.sentiment_analysis_prepare_data_glue_job_log_group.name
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--enable-observability-metrics"     = "true"
    "--enable-glue-datacatalog"          = "true"
    "--BUCKET"                           = aws_s3_bucket.sentiment_analysis_data_bucket.id
  }

  command {
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.sentiment_analysis_assets_bucket.id}/prepare_data.py"
  }
}

# ##################################################################################################
# Resources for Glue Job to prepare results
# ##################################################################################################

resource "aws_cloudwatch_log_group" "sentiment_analysis_prepare_results_glue_job_log_group" {
  name              = "/aws/lambda/${local.sentiment_analysis_prepare_results_glue_job_name}"
  retention_in_days = 7
}

resource "aws_glue_job" "sentiment_analysis_prepare_results_glue_job" {
  name     = local.sentiment_analysis_prepare_results_glue_job_name
  role_arn = aws_iam_role.sentiment_analysis_glue_role.arn

  glue_version      = "4.0"
  number_of_workers = 10
  worker_type       = "G.1X"

  default_arguments = {
    "--continuous-log-logGroup"          = aws_cloudwatch_log_group.sentiment_analysis_prepare_results_glue_job_log_group.name
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--enable-observability-metrics"     = "true"
    "--enable-glue-datacatalog"          = "true"
    "--BUCKET"                           = aws_s3_bucket.sentiment_analysis_data_bucket.id
  }

  command {
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.sentiment_analysis_assets_bucket.id}/prepare_results.py"
  }
}

# ##################################################################################################
# Resources for Comprehend
# ##################################################################################################

resource "aws_iam_role" "sentiment_analysis_comprehend_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}sentiment-analysis-comprehend-role" : null
  managed_policy_arns = [
    aws_iam_policy.sentiment_analysis_comprehend_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "comprehend.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "sentiment_analysis_comprehend_role_policy" {
  name = "${local.resource_prefix}sentiment-analysis-comprehend-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}"
        ]
      },
    ]
  })
}

# ##################################################################################################
# Resources for glue data catalog population
# ##################################################################################################

resource "aws_glue_catalog_database" "sentiment_analysis_catalog_database" {
  name = "${local.resource_prefix}sentiment-analysis-catalog-database"
}

resource "aws_iam_role" "sentiment_analysis_results_crawler_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}sentiment-analysis-results-crawler-role" : null
  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole",
    aws_iam_policy.sentiment_analysis_results_crawler_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "sentiment_analysis_results_crawler_role_policy" {
  name = "${local.resource_prefix}sentiment-analysis-results-crawler-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.sentiment_analysis_data_bucket.arn}/results/*"
        ]
      }
    ]
  })
}

resource "aws_glue_crawler" "sentiment_analysis_results_crawler" {
  database_name = aws_glue_catalog_database.sentiment_analysis_catalog_database.name
  table_prefix  = "${local.resource_prefix}sentiment-analysis-"
  name          = "${local.resource_prefix}sentiment-analysis-results-crawler"
  role          = aws_iam_role.sentiment_analysis_results_crawler_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.sentiment_analysis_data_bucket.id}/results/"
  }
}

# ##################################################################################################
# Resources for auto start
# ##################################################################################################

resource "aws_iam_role" "sentiment_analysis_event_target_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}sentiment-analysis-event-target-role" : null
  managed_policy_arns = [
    aws_iam_policy.sentiment_analysis_event_target_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "sentiment_analysis_event_target_role_policy" {
  name = "${local.resource_prefix}sentiment-analysis-event-target-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "states:StartExecution"
        ]
        Effect = "Allow"
        Resource = [
          aws_sfn_state_machine.sentiment_analysis_state_machine.arn
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "sentiment_analysis_event_rule" {
  name           = "${local.resource_prefix}sentiment-analysis-event-rule"
  description    = "Event rule to auto start sentiment analysis"
  event_bus_name = "default"
  state          = "ENABLED"

  event_pattern = jsonencode({
    source = ["aws.s3"],
    detail-type = [
      "Object Created"
    ],
    detail = {
      bucket = {
        name = [aws_s3_bucket.sentiment_analysis_data_bucket.bucket]
      },
      object = {
        key = [{ prefix = "input/" }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "sentiment_analysis_event_target" {
  rule      = aws_cloudwatch_event_rule.sentiment_analysis_event_rule.name
  target_id = "${local.resource_prefix}sentiment-analysis-event-target"
  arn       = aws_sfn_state_machine.sentiment_analysis_state_machine.arn
  role_arn  = aws_iam_role.sentiment_analysis_event_target_role.arn
  input_transformer {
    input_paths = {
      skipKey = "$.detail.object.key",
    }
    input_template = <<EOF
{
  "skipKey": "<skipKey>"
}
EOF
  }
}

# ##################################################################################################
# Resources for State Machine to perform sentiment analysis
# ##################################################################################################

resource "aws_iam_role" "sentiment_analysis_state_machine_role" {
  name = var.resource_prefix != "" ? "${var.resource_prefix}sentiment-analysis-state-machine-role" : null
  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole",
    aws_iam_policy.sentiment_analysis_state_machine_role_policy.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "sentiment_analysis_state_machine_role_policy" {
  name = "${local.resource_prefix}sentiment-analysis-state-machine-role-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "events:PutTargets",
          "events:DescribeRule",
          "events:PutRule",
          "glue:StartJobRun",
          "glue:GetJobRun",
          "ecs:DescribeTasks"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/*/*",
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/*",
          "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task/*/*"
        ]
      },
      {
        Action = [
          "iam:PassRole",
          "lambda:InvokeFunction",
          "comprehend:StartSentimentDetectionJob",
          "glue:StartCrawler"
        ]
        Effect = "Allow"
        Resource = [
          aws_iam_role.sentiment_analysis_comprehend_role.arn,
          "arn:aws:comprehend:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:sentiment-detection-job/*",
          aws_lambda_function.remove_all_files_from_s3_lambda.arn,
          aws_lambda_function.unzip_files_lambda.arn,
          aws_lambda_function.get_comprehend_job_status_lambda.arn,
          aws_lambda_function.get_crawler_run_status_lambda.arn,
          "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:crawler/*",
        ]
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Effect = "Allow"
        Resource = [
          "*"
        ]
      },
    ]
  })
}

resource "aws_sfn_state_machine" "sentiment_analysis_state_machine" {
  name     = local.sentiment_analysis_state_machine_name
  role_arn = aws_iam_role.sentiment_analysis_state_machine_role.arn

  definition = <<EOF
{
  "Comment": "Sentiment Analysis",
  "StartAt": "Remove Previous Data",
  "States": {
    "Remove Previous Data": {
      "Type": "Parallel",
      "Next": "Prepare Raw Data",
      "Branches": [
        {
          "StartAt": "Remove Data (input)",
          "States": {
            "Remove Data (input)": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "OutputPath": "$.Payload",
              "Parameters": {
                "FunctionName": "${aws_lambda_function.remove_all_files_from_s3_lambda.arn}",
                "Payload": {
                  "Bucket": "${aws_s3_bucket.sentiment_analysis_data_bucket.id}",
                  "Prefix": "input/",
                  "SkipKeys.$": "States.Array($.skipKey)",
                  "SkipIfNoSkipKeys": "true"
                }
              },
              "Retry": [
                {
                  "ErrorEquals": [
                    "Lambda.ServiceException",
                    "Lambda.AWSLambdaException",
                    "Lambda.SdkClientException",
                    "Lambda.TooManyRequestsException"
                  ],
                  "IntervalSeconds": 1,
                  "MaxAttempts": 3,
                  "BackoffRate": 2
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "Remove Data (prepared)",
          "States": {
            "Remove Data (prepared)": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "OutputPath": "$.Payload",
              "Parameters": {
                "FunctionName": "${aws_lambda_function.remove_all_files_from_s3_lambda.arn}",
                "Payload": {
                  "Bucket": "${aws_s3_bucket.sentiment_analysis_data_bucket.id}",
                  "Prefix": "prepared/"
                }
              },
              "Retry": [
                {
                  "ErrorEquals": [
                    "Lambda.ServiceException",
                    "Lambda.AWSLambdaException",
                    "Lambda.SdkClientException",
                    "Lambda.TooManyRequestsException"
                  ],
                  "IntervalSeconds": 1,
                  "MaxAttempts": 3,
                  "BackoffRate": 2
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "Remove Data (analyzed)",
          "States": {
            "Remove Data (analyzed)": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "OutputPath": "$.Payload",
              "Parameters": {
                "FunctionName": "${aws_lambda_function.remove_all_files_from_s3_lambda.arn}",
                "Payload": {
                  "Bucket": "${aws_s3_bucket.sentiment_analysis_data_bucket.id}",
                  "Prefix": "analyzed/"
                }
              },
              "Retry": [
                {
                  "ErrorEquals": [
                    "Lambda.ServiceException",
                    "Lambda.AWSLambdaException",
                    "Lambda.SdkClientException",
                    "Lambda.TooManyRequestsException"
                  ],
                  "IntervalSeconds": 1,
                  "MaxAttempts": 3,
                  "BackoffRate": 2
                }
              ],
              "End": true
            }
          }
        },
        {
          "StartAt": "Remove Data (results)",
          "States": {
            "Remove Data (results)": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "OutputPath": "$.Payload",
              "Parameters": {
                "FunctionName": "${aws_lambda_function.remove_all_files_from_s3_lambda.arn}",
                "Payload": {
                  "Bucket": "${aws_s3_bucket.sentiment_analysis_data_bucket.id}",
                  "Prefix": "results/"
                }
              },
              "Retry": [
                {
                  "ErrorEquals": [
                    "Lambda.ServiceException",
                    "Lambda.AWSLambdaException",
                    "Lambda.SdkClientException",
                    "Lambda.TooManyRequestsException"
                  ],
                  "IntervalSeconds": 1,
                  "MaxAttempts": 3,
                  "BackoffRate": 2
                }
              ],
              "End": true
            }
          }
        }
      ]
    },
    "Prepare Raw Data": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${local.sentiment_analysis_prepare_data_glue_job_name}"
      },
      "Next": "Detect sentiment"
    },
    "Detect sentiment": {
      "Type": "Task",
      "Parameters": {
        "DataAccessRoleArn": "${aws_iam_role.sentiment_analysis_comprehend_role.arn}",
        "InputDataConfig": {
          "S3Uri": "s3://${aws_s3_bucket.sentiment_analysis_data_bucket.id}/prepared/",
          "InputFormat": "ONE_DOC_PER_LINE"
        },
        "LanguageCode": "en",
        "OutputDataConfig": {
          "S3Uri": "s3://${aws_s3_bucket.sentiment_analysis_data_bucket.id}/analyzed/"
        },
        "JobName.$": "States.Format('${local.resource_prefix}sentiment-analysis-{}', $$.Execution.Name)"
      },
      "Resource": "arn:aws:states:::aws-sdk:comprehend:startSentimentDetectionJob",
      "Next": "Wait 10 seconds for Comprehend",
      "ResultSelector": {
        "JobId.$": "$.JobId"
      }
    },
    "Wait 10 seconds for Comprehend": {
      "Type": "Wait",
      "Seconds": 10,
      "Next": "Get Sentiment Job status"
    },
    "Get Sentiment Job status": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "Payload.$": "$",
        "FunctionName": "${aws_lambda_function.get_comprehend_job_status_lambda.arn}"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Next": "Sentiment Job done?",
      "OutputPath": "$.Payload"
    },
    "Sentiment Job done?": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.JobStatus",
          "StringEquals": "FAILED",
          "Next": "Sentiment Job Failed"
        },
        {
          "Variable": "$.JobStatus",
          "StringEquals": "COMPLETED",
          "Next": "Decompress Analyzed Data"
        }
      ],
      "Default": "Wait 10 seconds for Comprehend"
    },
    "Decompress Analyzed Data": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "OutputPath": "$.Payload",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.unzip_files_lambda.arn}",
        "Payload": {
          "Bucket": "${aws_s3_bucket.sentiment_analysis_data_bucket.id}",
          "Prefix": "analyzed/"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Next": "Prepare Final Data"
    },
    "Sentiment Job Failed": {
      "Type": "Fail"
    },
    "Prepare Final Data": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${local.sentiment_analysis_prepare_results_glue_job_name}"
      },
      "Next": "Start Crawler"
    },
    "Start Crawler": {
      "Type": "Task",
      "Parameters": {
        "Name": "${aws_glue_crawler.sentiment_analysis_results_crawler.name}"
      },
      "Resource": "arn:aws:states:::aws-sdk:glue:startCrawler",
      "Next": "Wait 10 seconds for Crawler"
    },
    "Wait 10 seconds for Crawler": {
      "Type": "Wait",
      "Seconds": 10,
      "Next": "Get Crawler Run Status"
    },
    "Get Crawler Run Status": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "OutputPath": "$.Payload",
      "Parameters": {
        "FunctionName": "${aws_lambda_function.get_crawler_run_status_lambda.arn}",
        "Payload": {
          "CrawlerName": "${aws_glue_crawler.sentiment_analysis_results_crawler.name}"
        }
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Next": "Crawler Run done?"
    },
    "Crawler Run done?": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.CrawlStatus",
          "StringEquals": "RUNNING",
          "Next": "Wait 10 seconds for Crawler"
        },
        {
          "Variable": "$.CrawlStatus",
          "StringEquals": "SUCCEEDED",
          "Next": "Go to End"
        }
      ],
      "Default": "Crawler Job Failed"
    },
    "Crawler Job Failed": {
      "Type": "Fail"
    },
    "Go to End": {
      "Type": "Pass",
      "End": true
    }
  }
}
EOF
}
