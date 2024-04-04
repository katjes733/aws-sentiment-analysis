provider "aws" {
  region  = var.aws_region
  profile = var.profile != "" ? var.profile : null
  default_tags {
    tags = {
      Owner = var.tag_owner
      Type  = var.tag_type
      Usage = var.tag_usage
    }
  }
}
