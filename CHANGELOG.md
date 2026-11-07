# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `subscriptions[*].grant_dead_letter_iam` (default `true`): for a subscription
  with `dead_letter_topic` set, grant the Pub/Sub service agent
  `roles/pubsub.publisher` on the dead letter topic and
  `roles/pubsub.subscriber` on the subscription. Dead lettering did nothing
  without these. Existing configurations that set `dead_letter_topic` will see
  two new IAM member resources per such subscription and a `google_project`
  data source read, which needs `resourcemanager.projects.get`. Set it to
  `false` if you already manage those bindings.
- `subscriptions[*].retry_policy` (`minimum_backoff`, `maximum_backoff`),
  `filter`, `enable_message_ordering` and `enable_exactly_once_delivery`,
  passed 1:1 to `google_pubsub_subscription`. All default to null, so existing
  plans do not change. Backoffs are validated as `"0s"`–`"600s"` with minimum
  not above maximum, and `filter` is capped at 256 characters.

### Changed

- The `id` output is now built from the topic's project and name so it is
  known at plan time. The value is the same `projects/<project>/topics/<name>`
  string as before.

- CI: bump actions to their current majors, pin tool versions, and restrict the
  workflow token to `contents: read`.
- CI: add Dependabot for GitHub Actions and the Terraform provider.
- Docs: pin the README usage `source` to a release tag; fix the LICENSE year.

## [1.0.0]

Initial release (`v0.1.0` points at the same commit).

[Unreleased]: https://github.com/moveeeax/terraform-google-pubsub/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/moveeeax/terraform-google-pubsub/releases/tag/v1.0.0
