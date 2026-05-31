#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)
OUTPUT = File.join(ROOT, "deliverables", "md-docs.js")

def first_heading(content, fallback)
  heading = content.each_line.find { |line| line.match?(/^#\s+\S/) }
  return fallback if heading.nil?

  heading.sub(/^#\s+/, "").strip
end

documents = Dir.chdir(ROOT) do
  Dir["docs/**/*.md"].sort.map do |path|
    content = File.read(path)
    fallback = File.basename(path, ".md").split("-").map(&:capitalize).join(" ")
    {
      path: path,
      title: first_heading(content, fallback),
      content: content
    }
  end
end

payload = {
  generated_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
  documents: documents.to_h { |doc| [doc[:path], doc] }
}

File.write(
  OUTPUT,
  "window.PALANTIR_MD_DOCS = #{JSON.pretty_generate(payload)};\n"
)

puts "Wrote #{OUTPUT} with #{documents.length} Markdown documents."
