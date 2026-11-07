# terraform-google-pubsub

Terraform module that manages a [Google Cloud](https://cloud.google.com/)
Pub/Sub topic (`google_pubsub_topic`) and an optional set of subscriptions
driven by a map input.

## Usage

```hcl
module "events_dlq" {
  source = "github.com/moveeeax/terraform-google-pubsub?ref=v1.0.0"

  project_id = var.project_id
  name       = "events-dlq"

  subscriptions = {
    "events-dlq-worker" = {}
  }
}

module "pubsub" {
  source = "github.com/moveeeax/terraform-google-pubsub?ref=v1.0.0"

  project_id = var.project_id
  name       = "events"

  # Lets a subscription seek back to a point before it was created.
  message_retention_duration = "86400s"

  subscriptions = {
    "events-worker" = {
      ack_deadline_seconds  = 30
      dead_letter_topic     = module.events_dlq.id
      max_delivery_attempts = 10

      # Back off between redeliveries instead of retrying immediately.
      retry_policy = {
        minimum_backoff = "10s"
        maximum_backoff = "300s"
      }
    }

    "events-orders" = {
      filter                       = "attributes.type = \"order\""
      enable_message_ordering      = true
      enable_exactly_once_delivery = true
    }
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Durability defaults

Two Pub/Sub defaults lose data quietly, so this module does not inherit them:

- **Subscription expiry.** If `expiration_policy` is not set, the API applies a
  31 day TTL and *deletes* the subscription once it has been inactive that
  long. Every message published afterwards is dropped with no error anywhere.
  This module defaults `expiration_ttl` to `""`, which means never expire. Set
  it explicitly (minimum `"86400s"`) if you actually want short lived
  subscriptions.
- **Poison messages.** With no `dead_letter_policy`, a message that always
  nacks is redelivered forever and, on an ordered subscription, blocks every
  later message on the same ordering key. Set `dead_letter_topic` and
  `max_delivery_attempts` to bound it.

Dead lettering additionally needs the Pub/Sub service agent
(`service-<project-number>@gcp-sa-pubsub.iam.gserviceaccount.com`) to hold
`roles/pubsub.publisher` on the dead letter topic and `roles/pubsub.subscriber`
on the source subscription. Without them messages are never forwarded and no
error is reported. For every subscription with `dead_letter_topic` set, the
module grants both with `google_pubsub_topic_iam_member` and
`google_pubsub_subscription_iam_member` (non-authoritative, other members are
left alone). It looks up the project number with the `google_project` data
source, so the caller needs `resourcemanager.projects.get` on the project.
Set `grant_dead_letter_iam = false` on a subscription to manage those bindings
yourself. Never grant `allUsers` or `allAuthenticatedUsers` on a Pub/Sub topic
or subscription.

Two caveats:

- `dead_letter_topic` must be known to be non-null at plan time, because it
  decides whether the IAM resources exist. This module's `id` output is built
  to be known at plan, so passing another instance's `id` works in a single
  apply. A topic id from an unrelated resource may not be; build it as
  `"projects/<project>/topics/${google_pubsub_topic.dlq.name}"` or set
  `grant_dead_letter_iam = false`.
- The publisher grant is created per subscription. When several subscriptions
  share one dead letter topic they each own an identical binding, so removing
  one subscription removes the binding for the others until the next apply
  re-creates it. Set `grant_dead_letter_iam = false` on all but one of them if
  that gap matters.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| google    | >= 5.0   |

The test suite under [`tests/`](tests) additionally needs Terraform >= 1.7 for
`mock_provider`. That is a test-only requirement; the module itself still works
on 1.5.

## Inputs

| Name                         | Description                                                            | Type          | Default | Required |
|------------------------------|------------------------------------------------------------------------|---------------|---------|:--------:|
| `project_id`                 | ID of the project in which to create the topic.                        | `string`      | n/a     |   yes    |
| `name`                       | Name of the Pub/Sub topic.                                             | `string`      | n/a     |   yes    |
| `message_retention_duration` | Topic level retention, `"600s"`–`"2678400s"`. Null disables it.        | `string`      | `null`  |    no    |
| `kms_key_name`               | Full Cloud KMS CryptoKey name for CMEK. Null uses Google-managed keys. | `string`      | `null`  |    no    |
| `subscriptions`              | Subscriptions keyed by name, see below.                                | `map(object)` | `{}`    |    no    |
| `labels`                     | Labels applied to the topic.                                           | `map(string)` | `{}`    |    no    |

### `subscriptions` object

| Attribute                      | Description                                                                                  | Type     | Default     |
|--------------------------------|----------------------------------------------------------------------------------------------|----------|-------------|
| `ack_deadline_seconds`         | How long a consumer has to ack a message. Must be 10–600.                                    | `number` | `10`        |
| `message_retention_duration`   | How long unacked messages are kept. Must be `"600s"`–`"2678400s"`.                           | `string` | `"604800s"` |
| `retain_acked_messages`        | Keep acked messages for replay via seek.                                                     | `bool`   | `false`     |
| `expiration_ttl`               | `""` never expires. Otherwise a TTL after which the subscription is DELETED.                 | `string` | `""`        |
| `dead_letter_topic`            | Full topic id to dead letter to. Null disables dead lettering.                               | `string` | `null`      |
| `max_delivery_attempts`        | 5–100. Only used when `dead_letter_topic` is set.                                            | `number` | `5`         |
| `grant_dead_letter_iam`        | Grant the Pub/Sub service agent the dead letter IAM roles. See above.                        | `bool`   | `true`      |
| `retry_policy`                 | `{ minimum_backoff, maximum_backoff }`, each `"0s"`–`"600s"`. Null retries immediately.      | `object` | `null`      |
| `filter`                       | Attribute filter, at most 256 bytes. Changing it replaces the subscription.                  | `string` | `null`      |
| `enable_message_ordering`      | Deliver messages with the same ordering key in order. Changing it replaces the subscription. | `bool`   | `null`      |
| `enable_exactly_once_delivery` | Exactly-once delivery. Null leaves the API default (off).                                    | `bool`   | `null`      |

## Outputs

| Name               | Description                                       |
|--------------------|---------------------------------------------------|
| `id`               | Identifier of the Pub/Sub topic.                 |
| `name`             | Name of the Pub/Sub topic.                       |
| `subscription_ids` | Identifiers of the subscriptions created.        |

## Development

```sh
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test
```

## License

[MIT](LICENSE)
