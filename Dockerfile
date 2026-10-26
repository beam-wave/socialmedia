# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.17.2-erlang-27.1-debian-trixie-20260610-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260610-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20260610-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker?repo=hexpm/elixir&os=debian&sort=elixir_version,erlang_version,os_version
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

# Bookworm, not trixie: Playwright's Chromium dependencies install on Debian 12
ARG ELIXIR_VERSION=1.17.2
ARG OTP_VERSION=26.2.5.9
ARG DEBIAN_VERSION=bookworm-20260610-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

# Node for the renderer and Claude Code (Playwright needs 20+, bookworm has 18)
FROM docker.io/node:22.11.0-bookworm-slim AS node

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
    fonts-noto-color-emoji \
  && rm -rf /var/lib/apt/lists/*

# Node runs the renderer (Playwright + Chromium) and the Claude Code CLI
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Claude Code: log in with CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token`)
RUN npm install -g @anthropic-ai/claude-code

# The agent, the channel templates and the renderer (see Socialmedia.Paths)
ENV PROJECT_ROOT=/app/project
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
COPY renderer/package.json renderer/package-lock.json /app/project/renderer/
RUN cd /app/project/renderer \
  && npm ci \
  && npx playwright install --with-deps chromium \
  && rm -rf /var/lib/apt/lists/*
COPY renderer/render.js /app/project/renderer/
COPY agent /app/project/agent
COPY channels /app/project/channels

# Claude keeps its settings and session files in $HOME. Trust the agent
# folder up front so its .claude/settings.json permissions apply headless.
RUN useradd --create-home --uid 1000 app \
  && echo '{"hasCompletedOnboarding":true,"projects":{"/app/project/agent":{"hasTrustDialogAccepted":true}}}' \
    > /home/app/.claude.json \
  && chown -R app /app /home/app
ENV HOME=/home/app

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=app:root /app/_build/${MIX_ENV}/rel/socialmedia ./

USER app

CMD ["/bin/sh", "-c", "/app/bin/migrate && /app/bin/server"]
