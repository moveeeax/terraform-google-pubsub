output "id" {
  description = "Identifier of the Pub/Sub topic."
  # Same "projects/{project}/topics/{name}" string as google_pubsub_topic.id,
  # but built from configured attributes so it is known at plan time. That lets
  # it be passed as another instance's dead_letter_topic in the same apply:
  # the dead letter IAM for_each has to know at plan time whether the topic is
  # null.
  value = "projects/${google_pubsub_topic.this.project}/topics/${google_pubsub_topic.this.name}"
}

output "name" {
  description = "Name of the Pub/Sub topic."
  value       = google_pubsub_topic.this.name
}

output "subscription_ids" {
  description = "Identifiers of the subscriptions created on the topic."
  value       = { for k, s in google_pubsub_subscription.this : k => s.id }
}
