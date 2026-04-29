# OpenTelemetry Java Agent

The agent JAR is downloaded automatically by the `Containerfile` at image-build time. The version is pinned via the `OTEL_AGENT_VERSION` build arg (default: `2.10.0`).

To override locally:

```bash
podman compose -f compose.yaml build --build-arg OTEL_AGENT_VERSION=2.11.0 service
```

The agent itself is not committed to this repository — it's downloaded by the `ADD` instruction in the Containerfile from the upstream GitHub release.

If you want to test a snapshot version, drop a JAR named `opentelemetry-javaagent.jar` here and modify the Containerfile to `COPY` it instead of `ADD`-ing from GitHub.

## Documentation

- Releases: https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases
- Configuration reference: https://opentelemetry.io/docs/zero-code/java/agent/configuration/
- Supported libraries: https://github.com/open-telemetry/opentelemetry-java-instrumentation/blob/main/docs/supported-libraries.md
