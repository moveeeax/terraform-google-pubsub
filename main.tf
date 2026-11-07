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

locals {
  # Subscriptions whose dead letter policy needs IAM granted by this module.
  # Keyed by subscription name, not by topic, so the keys stay known at plan
  # time even when dead_letter_topic comes from a topic created in the same
  # apply.
  dead_letter_iam = {
    for k, s in var.subscriptions : k => s
    if s.dead_letter_topic != null && s.grant_dead_letter_iam
  }
}

# The Pub/Sub service agent is named after the project number, not the ID. The
# IAM resources below exist only when this lookup does, so they index [0].
data "google_project" "this" {
  count = length(local.dead_letter_iam) > 0 ? 1 : 0

  project_id = var.project_id
}

# Dead lettering silently does nothing unless the service agent can publish to
# the dead letter topic and subscribe to (ack on) the source subscription.
resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  for_each = local.dead_letter_iam

  topic  = each.value.dead_letter_topic
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.this[0].number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "dead_letter_subscriber" {
  for_each = local.dead_letter_iam

  project      = var.project_id
  subscription = google_pubsub_subscription.this[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.this[0].number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
