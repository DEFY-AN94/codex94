#!/usr/bin/python3 -I
"""Read the Codex94 App target's version without running an Xcode build."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


PROJECT_FILE = "Codex94.xcodeproj/project.pbxproj"
MAX_PROJECT_BYTES = 1_048_576
SEMANTIC_VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")
POSITIVE_BUILD = re.compile(r"[1-9][0-9]*")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def object_body(project, object_id):
    pattern = re.compile(
        r"(?m)^\t\t" + re.escape(object_id) + r"(?:\s+/\*[^\n]*\*/)?\s*=\s*\{"
    )
    matches = list(pattern.finditer(project))
    require(len(matches) == 1, "The Xcode object graph is ambiguous")
    opening = project.find("{", matches[0].start(), matches[0].end())
    depth = 0
    for index in range(opening, len(project)):
        if project[index] == "{":
            depth += 1
        elif project[index] == "}":
            depth -= 1
            if depth == 0:
                return project[opening + 1:index]
    raise RuntimeError("The Xcode object graph is incomplete")


def unique_match(pattern, text, message):
    matches = re.findall(pattern, text, flags=re.MULTILINE | re.DOTALL)
    require(len(matches) == 1, message)
    return matches[0]


def parse_app_version(project):
    """Require one App target with matching explicit Debug/Release metadata."""
    target_ids = []
    for match in re.finditer(r"(?m)^\t\t([A-Za-z0-9]+)\s+/\*\s*Codex94\s*\*/\s*=\s*\{", project):
        body = object_body(project, match.group(1))
        if (re.search(r"(?m)^\s*isa\s*=\s*PBXNativeTarget\s*;", body)
                and re.search(r"(?m)^\s*name\s*=\s*Codex94\s*;", body)
                and re.search(
                    r'(?m)^\s*productType\s*=\s*"com\.apple\.product-type\.application"\s*;', body
                )):
            target_ids.append(match.group(1))
    require(len(target_ids) == 1, "The project must contain one Codex94 App target")
    target = object_body(project, target_ids[0])
    configuration_list_id = unique_match(
        r"^\s*buildConfigurationList\s*=\s*([A-Za-z0-9]+)\s+/\*[^\n]*\*/\s*;",
        target, "The Codex94 App target must have one configuration list",
    )
    configuration_list = object_body(project, configuration_list_id)
    require(re.search(r"(?m)^\s*isa\s*=\s*XCConfigurationList\s*;", configuration_list) is not None,
            "The Codex94 App configuration list has the wrong type")
    raw_configurations = unique_match(
        r"\bbuildConfigurations\s*=\s*\(([^)]*)\)\s*;",
        configuration_list, "The Codex94 App configuration list is ambiguous",
    )
    configurations = re.findall(
        r"([A-Za-z0-9]+)\s+/\*\s*(Debug|Release)\s*\*/", raw_configurations
    )
    require(len(configurations) == 2 and {name for _, name in configurations} == {"Debug", "Release"},
            "The Codex94 App target must have unique Debug and Release configurations")

    values = {}
    for configuration_id, expected_name in configurations:
        configuration = object_body(project, configuration_id)
        require(re.search(r"(?m)^\s*isa\s*=\s*XCBuildConfiguration\s*;", configuration) is not None,
                "The Codex94 App build configuration has the wrong type")
        actual_name = unique_match(
            r"^\s*name\s*=\s*([^;\n]+)\s*;", configuration,
            "The Codex94 App build configuration must have one name",
        ).strip().strip('"')
        require(actual_name == expected_name, "The Codex94 App configuration name changed")
        settings = unique_match(
            r"^\s*buildSettings\s*=\s*\{(.*?)^\s*\}\s*;",
            configuration, "The Codex94 App build settings are ambiguous",
        )
        version = unique_match(
            r"^\s*MARKETING_VERSION\s*=\s*([^;\n]+)\s*;", settings,
            "The Codex94 App configuration must define one marketing version",
        ).strip()
        build = unique_match(
            r"^\s*CURRENT_PROJECT_VERSION\s*=\s*([^;\n]+)\s*;", settings,
            "The Codex94 App configuration must define one build number",
        ).strip()
        require(SEMANTIC_VERSION.fullmatch(version) is not None,
                "The Codex94 App marketing version must be semantic")
        require(POSITIVE_BUILD.fullmatch(build) is not None,
                "The Codex94 App build number must be a positive integer")
        values[expected_name] = (version, build)
    require(values["Debug"] == values["Release"],
            "Codex94 Debug and Release version/build must match")
    return values["Debug"]


def git_output(repository, arguments, maximum_bytes):
    result = subprocess.run(
        ["/usr/bin/git", *arguments], cwd=repository,
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        check=False,
    )
    require(result.returncode == 0 and 0 < len(result.stdout) <= maximum_bytes,
            "Could not read the requested Git object")
    return result.stdout


def read_app_version(repository, revision=None):
    """Read local edits by default, or the exact checked-out commit for CI."""
    repository = Path(repository)
    if revision is not None:
        require(re.fullmatch(r"[0-9a-f]{40}", revision) is not None,
                "The source revision must be a full commit SHA")
        head = git_output(repository, ["rev-parse", "HEAD"], 128).decode("ascii").strip()
        require(head == revision, "The checked-out HEAD must equal the requested source revision")
        payload = git_output(repository, ["show", revision + ":" + PROJECT_FILE], MAX_PROJECT_BYTES)
    else:
        source = repository / PROJECT_FILE
        require(source == source.resolve(strict=True) and source.is_file(),
                "The project must be a regular file without symlink traversal")
        with source.open("rb") as stream:
            payload = stream.read(MAX_PROJECT_BYTES + 1)
    require(0 < len(payload) <= MAX_PROJECT_BYTES, "The project exceeded its size bound")
    return parse_app_version(payload.decode("utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", help="Read this exact checked-out commit instead of local edits")
    arguments = parser.parse_args()
    version, build = read_app_version(Path(__file__).resolve().parents[1], arguments.revision)
    print(json.dumps({"version": version, "build": build}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, RuntimeError) as error:
        print("Release metadata failed: " + str(error), file=sys.stderr)
        sys.exit(1)
