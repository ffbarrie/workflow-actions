#!/usr/bin/env ruby
# Validates every action.yml and .github/workflows/*.yml file parses as
# YAML. Cheap, fast, first-line check — the kind of thing that would have
# caught, e.g., a description string starting with a bare quote breaking
# the rest of the line (a real bug in an earlier version of this repo).

require "yaml"

files = Dir.glob("actions/*/action.yml") + Dir.glob(".github/workflows/*.yml")
abort "no action.yml or workflow files found — run from the repo root" if files.empty?

failures = []
files.sort.each do |file|
  YAML.load_file(file)
  puts "OK   #{file}"
rescue Psych::SyntaxError => e
  failures << [file, e.message]
  puts "FAIL #{file}: #{e.message}"
end

if failures.any?
  warn "\n#{failures.size} file(s) failed to parse."
  exit 1
end
