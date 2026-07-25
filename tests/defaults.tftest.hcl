# Requires Terraform >= 1.7 for mock_provider. This is a test-only requirement:
# the module itself still supports the required_version declared in versions.tf.
# Run with: terraform test

mock_provider "google" {}

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
