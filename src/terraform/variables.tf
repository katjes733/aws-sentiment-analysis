variable "aws_region" {
  description = "The AWS region for deployment."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-(gov-){0,1}(north|northeast|east|southeast|south|southwest|west|northwest|central)-[1-9]{1}$", var.aws_region))
    error_message = "Must be a valid AWS region."
  }
}

variable "profile" {
  description = "The AWS profile to use for deployment. If empty, the default profile will be used automatically."
  type        = string
  default     = ""
}

variable "tag_owner" {
  description = "value"
  type        = string

  validation {
    condition     = can(regex("^[\\w\\.]+\\@[\\w]+\\.[a-z]+$", var.tag_owner))
    error_message = "Must be a valid email address for the owner."
  }
}

variable "tag_type" {
  description = "value"
  type        = string
  default     = "Internal"

  validation {
    condition     = can(regex("^Internal|External$", var.tag_type))
    error_message = "Must be one of the following values only: Internal or External."
  }
}

variable "tag_usage" {
  description = "value"
  type        = string

  validation {
    condition     = can(regex("^Playground|Development|Qualification|Production|Control Tower$", var.tag_usage))
    error_message = "Must be one of the following values only: Playground, Development, Qualification, Production or Control Tower."
  }
}

variable "resource_prefix" {
  description = "The prefix for all resources. If empty, uniquenss of resource names is ensured."
  type        = string
  default     = "mac-"

  validation {
    condition     = can(regex("^$|^[a-z0-9-]{0,7}$", var.resource_prefix))
    error_message = "The resource_prefix must be empty or not be longer that 7 characters containing only the following characters: a-z0-9- ."
  }
}
