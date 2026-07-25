terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Dead letter topic. Messages the worker subscription cannot process land here
# instead of being redelivered forever.
module "dead_letter" {
  source = "../.."

  project_id = var.project_id
  name       = "example-topic-dlq"

  subscriptions = {
    "example-topic-dlq-sub" = {}
  }
}

module "pubsub" {
  source = "../.."

  project_id = var.project_id
  name       = "example-topic"

  # Topic level retention lets a new or reset subscription seek back in time.
  message_retention_duration = "86400s"

  subscriptions = {
    "example-sub" = {
      ack_deadline_seconds  = 20
      dead_letter_topic     = module.dead_letter.id
      max_delivery_attempts = 10
    }
  }
}

# Dead lettering also requires the Pub/Sub service agent to be able to publish
# to the dead letter topic and to subscribe to the source subscription:
#   roles/pubsub.publisher  on module.dead_letter.id
#   roles/pubsub.subscriber on the source subscription
# for service-<project-number>@gcp-sa-pubsub.iam.gserviceaccount.com.
# Grant those with google_pubsub_topic_iam_member / _subscription_iam_member.

variable "project_id" {
  description = "Project ID to deploy the example topic into."
  type        = string
}

variable "region" {
  description = "Region for the google provider."
  type        = string
  default     = "us-central1"
}

output "topic_id" {
  value = module.pubsub.id
}

output "dead_letter_topic_id" {
  value = module.dead_letter.id
}
