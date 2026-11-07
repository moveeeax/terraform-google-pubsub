variable "project_id" {
  description = "ID of the project in which to create the topic."
  type        = string
}

variable "name" {
  description = "Name of the Pub/Sub topic."
  type        = string
}

variable "message_retention_duration" {
  description = <<-EOT
    How long the topic itself retains published messages, as a seconds duration
    such as "86400s". Topic retention is what lets a subscription seek back to
    a point before it was created; null leaves it disabled, in which case a
    message is unrecoverable once every existing subscription has acked it.
    Must be between "600s" (10 minutes) and "2678400s" (31 days).
  EOT
  type        = string
  default     = null

  validation {
    condition = var.message_retention_duration == null || (
      can(regex("^[0-9]+(\\.[0-9]{1,9})?s$", var.message_retention_duration))
      && try(tonumber(trimsuffix(var.message_retention_duration, "s")) >= 600, false)
      && try(tonumber(trimsuffix(var.message_retention_duration, "s")) <= 2678400, false)
    )
    error_message = "message_retention_duration must be a seconds duration between \"600s\" and \"2678400s\", e.g. \"86400s\"."
  }
}

variable "kms_key_name" {
  description = <<-EOT
    Full resource name of a Cloud KMS CryptoKey used to encrypt message data at
    rest (CMEK), e.g. "projects/p/locations/global/keyRings/r/cryptoKeys/k".
    Null uses Google-managed encryption keys.
  EOT
  type        = string
  default     = null

  validation {
    condition = var.kms_key_name == null || can(regex(
      "^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$",
      var.kms_key_name
    ))
    error_message = "kms_key_name must be a full CryptoKey resource name: projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "subscriptions" {
  description = <<-EOT
    Subscriptions to create on the topic, keyed by subscription name.

    - ack_deadline_seconds: 10-600, how long a consumer has to ack a message.
    - message_retention_duration: how long unacked messages are kept.
    - retain_acked_messages: keep acked messages for replay via seek.
    - expiration_ttl: "" (the default) never expires the subscription. Any
      other value is a TTL after which Pub/Sub DELETES the subscription once it
      has been inactive that long; minimum "86400s".
    - dead_letter_topic: full topic id ("projects/<project>/topics/<topic>") to
      forward a message to after max_delivery_attempts failed deliveries. Null
      disables dead lettering, which means a poison message redelivers forever.
    - max_delivery_attempts: 5-100, only used when dead_letter_topic is set.
    - grant_dead_letter_iam: when dead_letter_topic is set, grant the Pub/Sub
      service agent roles/pubsub.publisher on the dead letter topic and
      roles/pubsub.subscriber on this subscription. Without both, Pub/Sub
      cannot forward messages. Set false if you manage those bindings
      elsewhere.
  EOT
  type = map(object({
    ack_deadline_seconds       = optional(number, 10)
    message_retention_duration = optional(string, "604800s")
    retain_acked_messages      = optional(bool, false)
    expiration_ttl             = optional(string, "")
    dead_letter_topic          = optional(string)
    max_delivery_attempts      = optional(number, 5)
    grant_dead_letter_iam      = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for s in values(var.subscriptions) :
      s.ack_deadline_seconds >= 10 && s.ack_deadline_seconds <= 600
    ])
    error_message = "subscriptions[*].ack_deadline_seconds must be between 10 and 600 seconds."
  }

  validation {
    condition = alltrue([
      for s in values(var.subscriptions) :
      can(regex("^[0-9]+(\\.[0-9]{1,9})?s$", s.message_retention_duration))
      && try(tonumber(trimsuffix(s.message_retention_duration, "s")) >= 600, false)
      && try(tonumber(trimsuffix(s.message_retention_duration, "s")) <= 2678400, false)
    ])
    error_message = "subscriptions[*].message_retention_duration must be a seconds duration between \"600s\" and \"2678400s\", e.g. \"604800s\"."
  }

  validation {
    condition = alltrue([
      for s in values(var.subscriptions) :
      s.expiration_ttl == "" || (
        can(regex("^[0-9]+(\\.[0-9]{1,9})?s$", s.expiration_ttl))
        && try(tonumber(trimsuffix(s.expiration_ttl, "s")) >= 86400, false)
      )
    ])
    error_message = "subscriptions[*].expiration_ttl must be \"\" (never expire) or a seconds duration of at least \"86400s\"."
  }

  validation {
    condition = alltrue([
      for s in values(var.subscriptions) :
      s.dead_letter_topic == null || (
        s.max_delivery_attempts >= 5 && s.max_delivery_attempts <= 100
      )
    ])
    error_message = "subscriptions[*].max_delivery_attempts must be between 5 and 100 when dead_letter_topic is set."
  }
}

variable "labels" {
  description = "Labels applied to the topic."
  type        = map(string)
  default     = {}
}
