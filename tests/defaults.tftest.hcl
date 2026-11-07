# Requires Terraform >= 1.7 for mock_provider. This is a test-only requirement:
# the module itself still supports the required_version declared in versions.tf.
# Run with: terraform test

mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789"
    }
  }
}

variables {
  project_id = "test-project"
  name       = "events"
}

run "subscriptions_never_expire_by_default" {
  variables {
    subscriptions = {
      worker = {}
    }
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].expiration_policy[0].ttl == ""
    error_message = "Default subscription must set expiration_policy.ttl to \"\"; otherwise the Pub/Sub API deletes it after 31 days of inactivity."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].ack_deadline_seconds == 10
    error_message = "Default ack_deadline_seconds should remain 10."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].message_retention_duration == "604800s"
    error_message = "Default message_retention_duration should remain 604800s."
  }

  assert {
    condition     = length(google_pubsub_subscription.this["worker"].dead_letter_policy) == 0
    error_message = "No dead_letter_policy block should be emitted when dead_letter_topic is unset."
  }
}

run "explicit_expiration_ttl_is_honoured" {
  variables {
    subscriptions = {
      ephemeral = {
        expiration_ttl = "172800s"
      }
    }
  }

  assert {
    condition     = google_pubsub_subscription.this["ephemeral"].expiration_policy[0].ttl == "172800s"
    error_message = "expiration_ttl must be passed through to expiration_policy.ttl."
  }
}

run "dead_letter_policy_is_wired_up" {
  variables {
    subscriptions = {
      worker = {
        dead_letter_topic     = "projects/test-project/topics/events-dlq"
        max_delivery_attempts = 10
      }
    }
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].dead_letter_policy[0].dead_letter_topic == "projects/test-project/topics/events-dlq"
    error_message = "dead_letter_topic must be forwarded to dead_letter_policy."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].dead_letter_policy[0].max_delivery_attempts == 10
    error_message = "max_delivery_attempts must be forwarded to dead_letter_policy."
  }
}

run "dead_letter_iam_is_granted_to_service_agent" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        dead_letter_topic = "projects/test-project/topics/events-dlq"
      }
    }
  }

  assert {
    condition     = google_pubsub_topic_iam_member.dead_letter_publisher["worker"].topic == "projects/test-project/topics/events-dlq"
    error_message = "The publisher grant must target the dead letter topic."
  }

  assert {
    condition     = google_pubsub_topic_iam_member.dead_letter_publisher["worker"].role == "roles/pubsub.publisher"
    error_message = "The dead letter topic grant must be roles/pubsub.publisher."
  }

  assert {
    condition     = google_pubsub_topic_iam_member.dead_letter_publisher["worker"].member == "serviceAccount:service-123456789@gcp-sa-pubsub.iam.gserviceaccount.com"
    error_message = "The publisher grant must go to the project's Pub/Sub service agent."
  }

  assert {
    condition     = google_pubsub_subscription_iam_member.dead_letter_subscriber["worker"].subscription == "worker"
    error_message = "The subscriber grant must target the source subscription."
  }

  assert {
    condition     = google_pubsub_subscription_iam_member.dead_letter_subscriber["worker"].role == "roles/pubsub.subscriber"
    error_message = "The source subscription grant must be roles/pubsub.subscriber."
  }

  assert {
    condition     = google_pubsub_subscription_iam_member.dead_letter_subscriber["worker"].member == "serviceAccount:service-123456789@gcp-sa-pubsub.iam.gserviceaccount.com"
    error_message = "The subscriber grant must go to the project's Pub/Sub service agent."
  }
}

run "dead_letter_iam_can_be_disabled" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        dead_letter_topic     = "projects/test-project/topics/events-dlq"
        grant_dead_letter_iam = false
      }
    }
  }

  assert {
    condition     = length(google_pubsub_topic_iam_member.dead_letter_publisher) == 0 && length(google_pubsub_subscription_iam_member.dead_letter_subscriber) == 0
    error_message = "No dead letter IAM should be created when grant_dead_letter_iam is false."
  }

  assert {
    condition     = length(data.google_project.this) == 0
    error_message = "The project lookup should be skipped when no dead letter IAM is needed."
  }
}

run "no_dead_letter_iam_without_dead_letter_topic" {
  command = plan

  variables {
    subscriptions = {
      worker = {}
    }
  }

  assert {
    condition     = length(google_pubsub_topic_iam_member.dead_letter_publisher) == 0 && length(google_pubsub_subscription_iam_member.dead_letter_subscriber) == 0
    error_message = "No dead letter IAM should be created for a subscription without dead_letter_topic."
  }

  assert {
    condition     = length(data.google_project.this) == 0
    error_message = "The project lookup should be skipped when no subscription dead letters."
  }
}

run "topic_id_is_known_at_plan" {
  command = plan

  assert {
    condition     = output.id == "projects/test-project/topics/events"
    error_message = "output.id must be known at plan time so it can feed another instance's dead_letter_topic."
  }
}

run "delivery_options_default_to_unset" {
  command = plan

  variables {
    subscriptions = {
      worker = {}
    }
  }

  assert {
    condition     = length(google_pubsub_subscription.this["worker"].retry_policy) == 0
    error_message = "No retry_policy block should be emitted when retry_policy is unset."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].filter == null
    error_message = "filter should be null by default."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].enable_message_ordering == null
    error_message = "enable_message_ordering should be null by default."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].enable_exactly_once_delivery == null
    error_message = "enable_exactly_once_delivery should be null by default."
  }
}

run "delivery_options_are_wired_up" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        retry_policy = {
          minimum_backoff = "5s"
          maximum_backoff = "300s"
        }
        filter                       = "attributes.type = \"order\""
        enable_message_ordering      = true
        enable_exactly_once_delivery = true
      }
    }
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].retry_policy[0].minimum_backoff == "5s"
    error_message = "retry_policy.minimum_backoff must be forwarded to the subscription."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].retry_policy[0].maximum_backoff == "300s"
    error_message = "retry_policy.maximum_backoff must be forwarded to the subscription."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].filter == "attributes.type = \"order\""
    error_message = "filter must be forwarded to the subscription."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].enable_message_ordering == true
    error_message = "enable_message_ordering must be forwarded to the subscription."
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].enable_exactly_once_delivery == true
    error_message = "enable_exactly_once_delivery must be forwarded to the subscription."
  }
}

run "empty_retry_policy_uses_api_backoff_defaults" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        retry_policy = {}
      }
    }
  }

  assert {
    condition     = length(google_pubsub_subscription.this["worker"].retry_policy) == 1
    error_message = "An empty retry_policy object should still emit the block so the API's exponential backoff applies."
  }
}

run "topic_cmek_defaults_to_google_managed" {
  assert {
    condition     = google_pubsub_topic.this.kms_key_name == null
    error_message = "kms_key_name should be null unless a CMEK key is supplied."
  }
}

run "topic_cmek_is_wired_up" {
  variables {
    kms_key_name = "projects/test-project/locations/global/keyRings/ring/cryptoKeys/key"
  }

  assert {
    condition     = google_pubsub_topic.this.kms_key_name == "projects/test-project/locations/global/keyRings/ring/cryptoKeys/key"
    error_message = "kms_key_name must be applied to the topic."
  }
}

run "rejects_ack_deadline_below_minimum" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        ack_deadline_seconds = 5
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_ack_deadline_above_maximum" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        ack_deadline_seconds = 601
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_expiration_ttl_below_one_day" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        expiration_ttl = "3600s"
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_malformed_expiration_ttl" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        expiration_ttl = "30 days"
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_out_of_range_max_delivery_attempts" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        dead_letter_topic     = "projects/test-project/topics/events-dlq"
        max_delivery_attempts = 1
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_out_of_range_subscription_retention" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        message_retention_duration = "60s"
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_malformed_topic_retention" {
  command = plan

  variables {
    message_retention_duration = "1d"
  }

  expect_failures = [var.message_retention_duration]
}

run "rejects_malformed_kms_key_name" {
  command = plan

  variables {
    kms_key_name = "my-key"
  }

  expect_failures = [var.kms_key_name]
}

run "rejects_retry_backoff_above_maximum" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        retry_policy = {
          maximum_backoff = "601s"
        }
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_malformed_retry_backoff" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        retry_policy = {
          minimum_backoff = "10"
        }
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_minimum_backoff_above_maximum_backoff" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        retry_policy = {
          minimum_backoff = "60s"
          maximum_backoff = "30s"
        }
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_filter_longer_than_256" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        filter = "attributes.k = \"${join("", [for i in range(250) : "x"])}\""
      }
    }
  }

  expect_failures = [var.subscriptions]
}

run "accepts_retry_backoff_bounds_and_empty_filter" {
  command = plan

  variables {
    subscriptions = {
      worker = {
        retry_policy = {
          minimum_backoff = "0s"
          maximum_backoff = "600s"
        }
        filter = ""
      }
      only_min = {
        retry_policy = {
          minimum_backoff = "2.5s"
        }
      }
    }
  }

  assert {
    condition     = google_pubsub_subscription.this["worker"].retry_policy[0].maximum_backoff == "600s"
    error_message = "Boundary retry_policy values must be accepted."
  }
}
