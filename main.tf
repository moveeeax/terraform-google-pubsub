resource "google_pubsub_topic" "this" {
  project                    = var.project_id
  name                       = var.name
  message_retention_duration = var.message_retention_duration
  kms_key_name               = var.kms_key_name
  labels                     = var.labels
}

resource "google_pubsub_subscription" "this" {
  for_each = var.subscriptions

  project                    = var.project_id
  name                       = each.key
  topic                      = google_pubsub_topic.this.id
  ack_deadline_seconds       = each.value.ack_deadline_seconds
  message_retention_duration = each.value.message_retention_duration
  retain_acked_messages      = each.value.retain_acked_messages

  # When expiration_policy is omitted the Pub/Sub API applies a 31 day TTL and
  # *deletes* the subscription after 31 days without an active pull/push
  # connection, silently dropping every message published afterwards. An empty
  # ttl disables expiry, which is the default this module ships.
  expiration_policy {
    ttl = each.value.expiration_ttl
  }

  # Without a dead letter policy a message that always nacks (a poison message)
  # is redelivered forever and, on an ordered subscription, blocks every later
  # message on the same ordering key.
  dynamic "dead_letter_policy" {
    for_each = each.value.dead_letter_topic == null ? [] : [each.value]

    content {
      dead_letter_topic     = dead_letter_policy.value.dead_letter_topic
      max_delivery_attempts = dead_letter_policy.value.max_delivery_attempts
    }
  }
}
