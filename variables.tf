variable "region" {
  type        = string
  default     = "eu-west-3"
  description = "AWS region"
}

variable "cidr" {
  type        = string
  default     = "10.10.0.0/22"
  description = "cidr for eks-vpc"
}






