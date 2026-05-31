#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

ruby - "$@" <<'RUBY'
require "yaml"

SELF_TEST = ARGV.include?("--self-test")
CATALOG_PATH = "docs/catalog.yml"

def array(value)
  value.nil? ? [] : Array(value)
end

def local_path?(value)
  value.is_a?(String) && value.start_with?("docs/")
end

def validate_catalog(data)
  failures = []
  docs = data["documents"]

  unless docs.is_a?(Array)
    return ["catalog documents must be an array"]
  end

  ids = {}
  paths = {}
  status_vocab = array(data["status_vocabulary"])
  type_vocab = array(data["type_vocabulary"])

  docs.each_with_index do |doc, index|
    label = doc["id"] || "document[#{index}]"
    id = doc["id"]
    path = doc["path"]

    failures << "#{label}: missing id" if id.to_s.empty?
    failures << "#{label}: duplicate id #{id}" if id && ids.key?(id)
    ids[id] = true if id

    failures << "#{label}: missing path" if path.to_s.empty?
    failures << "#{label}: duplicate path #{path}" if path && paths.key?(path)
    paths[path] = true if path

    failures << "#{label}: missing document path #{path}" if path && !File.exist?(path)

    if status_vocab.any? && !status_vocab.include?(doc["status"])
      failures << "#{label}: invalid status #{doc["status"].inspect}"
    end

    if type_vocab.any? && !type_vocab.include?(doc["type"])
      failures << "#{label}: invalid type #{doc["type"].inspect}"
    end

    %w[source_refs related_docs supersedes].each do |field|
      array(doc[field]).each do |ref|
        failures << "#{label}: missing #{field} path #{ref}" if local_path?(ref) && !File.exist?(ref)
      end
    end

    ref = doc["superseded_by"]
    failures << "#{label}: missing superseded_by path #{ref}" if local_path?(ref) && !File.exist?(ref)
  end

  docs.each do |doc|
    label = doc["id"] || doc["path"] || "unknown document"

    %w[source_refs related_docs supersedes].each do |field|
      array(doc[field]).each do |ref|
        failures << "#{label}: uncataloged #{field} path #{ref}" if local_path?(ref) && File.exist?(ref) && !paths.key?(ref)
      end
    end

    ref = doc["superseded_by"]
    failures << "#{label}: uncataloged superseded_by path #{ref}" if local_path?(ref) && File.exist?(ref) && !paths.key?(ref)
  end

  tracked = `git ls-files "docs/catalog.yml" "docs/index.md" "docs/library/**/*.md" "docs/topics/*.md" "docs/raw/*.md" "docs/synthesis/*.md" "docs/superpowers/**/*.md"`.split("\n")
  catalog_paths = docs.map { |doc| doc["path"] }
  missing_tracked = tracked - catalog_paths
  failures << "missing catalog entries for tracked docs: #{missing_tracked.join(", ")}" unless missing_tracked.empty?

  failures
end

def markdown_link_targets(path)
  text = File.read(path)
  text.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.map do |target|
    target = target.sub(/\A<(.+)>\z/, "\\1")
    next if target.start_with?("http://", "https://", "mailto:", "#")

    local = target.split("#", 2).first
    next if local.nil? || local.empty?

    [target, File.expand_path(local, File.dirname(path))]
  end.compact
end

def validate_markdown_links
  failures = []
  pages = ["docs/index.md"] + Dir["docs/library/**/*.md"] + Dir["docs/topics/**/*.md"]

  pages.each do |page|
    next unless File.exist?(page)

    markdown_link_targets(page).each do |target, resolved|
      failures << "#{page}: missing local link #{target}" unless File.exist?(resolved)
    end
  end

  failures
end

data = YAML.load_file(CATALOG_PATH)
failures = validate_catalog(data) + validate_markdown_links

if SELF_TEST
  mutated = Marshal.load(Marshal.dump(data))
  mutated["documents"] << {
    "id" => "self-test-missing-path",
    "path" => "docs/__missing_self_test__.md",
    "type" => "raw",
    "status" => "reviewed"
  }
  self_test_failures = validate_catalog(mutated)
  unless self_test_failures.any? { |failure| failure.include?("docs/__missing_self_test__.md") }
    failures << "self-test failed: missing path was not detected"
  end
end

if failures.empty?
  puts SELF_TEST ? "doc library validation passed, including missing-path self-test" : "doc library validation passed"
else
  warn failures.join("\n")
  exit 1
end
RUBY
