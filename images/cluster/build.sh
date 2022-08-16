#!/usr/bin/env bash
# Copyright 2022 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DIR="$(dirname "${BASH_SOURCE[0]}")"
DIR="$(realpath "${DIR}")"
ROOT_DIR="$(realpath "${DIR}/../..")"
DOCKERFILE="$(realpath "${DIR}/Dockerfile" --relative-to="${ROOT_DIR}")"

DRY_RUN=false
PUSH=false
IMAGES=()
PLATFORMS=()
VERSION=""
KUBE_VERSIONS=()

function usage() {
  echo "Usage: ${0} [--help] [--version <version>] [--kube-version <kube-version> ...] [--image <image> ...] [--platform <platform> ...] [--push] [--dry-run]"
  echo "  --version <version> is kwok version, is required"
  echo "  --kube-version <kube-version> is kubernetes version, is required"
  echo "  --image <image> is image, is required"
  echo "  --platform <platform> is multi-platform capable for image"
  echo "  --push will push image to registry"
  echo "  --dry-run just show what would be done"
}

function args() {
  local arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "${arg}" in
    --kube-version | --kube-version=*)
      [[ "${arg#*=}" != "${arg}" ]] && KUBE_VERSIONS+=("${arg#*=}") || { KUBE_VERSIONS+=("${2}") && shift; }
      shift
      ;;
    --version | --version=*)
      [[ "${arg#*=}" != "${arg}" ]] && VERSION="${arg#*=}" || { VERSION="${2}" && shift; }
      shift
      ;;
    --image | --image=*)
      [[ "${arg#*=}" != "${arg}" ]] && IMAGES+=("${arg#*=}") || { IMAGES+=("${2}") && shift; }
      shift
      ;;
    --platform | --platform=*)
      [[ "${arg#*=}" != "${arg}" ]] && PLATFORMS+=("${arg#*=}") || { PLATFORMS+=("${2}") && shift; }
      shift
      ;;
    --push | --push=*)
      [[ "${arg#*=}" != "${arg}" ]] && PUSH="${arg#*=}" || PUSH="true"
      shift
      ;;
    --dry-run | --dry-run=*)
      [[ "${arg#*=}" != "${arg}" ]] && DRY_RUN="${arg#*=}" || DRY_RUN="true"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}"
      usage
      exit 1
      ;;
    esac
  done

  if [[ "${VERSION}" == "" ]]; then
    echo "--version is required"
    usage
    exit 1
  fi

  if [[ "${#KUBE_VERSIONS}" -eq 0 ]]; then
    echo "--kube-version is required"
    usage
    exit 1
  fi

  if [[ "${#IMAGES}" -eq 0 ]]; then
    echo "--image is required"
    usage
    exit 1
  fi
}

function dry_run() {
  echo "${@}"
  if [[ "${DRY_RUN}" != "true" ]]; then
    eval "${@}"
  fi
}

function main() {
  local extra_args

  if [[ "${#PLATFORMS}" -ne 0 ]]; then
    export DOCKER_CLI_EXPERIMENTAL=enabled
    if [[ "${DRY_RUN}" != "true" ]]; then
      if ! docker buildx inspect --builder kwok >/dev/null 2>&1; then
        docker buildx create --use --name kwok >/dev/null 2>&1
        trap 'docker buildx rm kwok' EXIT
      fi
    fi
  fi

  for kube_version in "${KUBE_VERSIONS[@]}"; do
    extra_args=(
      "--build-arg=kube_version=${kube_version}"
      "--build-arg=kwok_version=${VERSION}"
    )

    for image in "${IMAGES[@]}"; do
      extra_args+=(
        "--tag=${image}:${VERSION}-k8s.${kube_version}"
      )
    done

    if [[ "${#PLATFORMS}" -eq 0 ]]; then
      dry_run docker build \
        "${extra_args[@]}" \
        -f "${DOCKERFILE}" \
        . || return 1

      if [[ "${PUSH}" == "true" ]]; then
        for image in "${IMAGES[@]}"; do
          dry_run docker push "${image}:${VERSION}-k8s.${kube_version}"
        done
      fi
    else
      for platform in "${PLATFORMS[@]}"; do
        extra_args+=(
          "--platform=${platform}"
        )
      done
      if [[ "${PUSH}" == "true" ]]; then
        extra_args+=("--push")
      fi
      dry_run docker buildx build \
        "${extra_args[@]}" \
        -f "${DOCKERFILE}" \
        .
    fi
  done
}

args "$@"

cd "${ROOT_DIR}" && main
