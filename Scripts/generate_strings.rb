#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Builds Localizable.xcstrings for each framework by scanning the sources.
#
# Xcode extracts strings into a String Catalog automatically when it can see
# a literal passed to String(localized:) or Text(...). Our sources call a
# LocalizedString(_:comment:) wrapper — the same one CGMBLEKit, G7SensorKit
# and LibreLoop use — so the literal is an argument to our function and the
# extractor cannot see through it. This generates the catalog instead, and
# keeps the comments as translator notes.
#
# Existing translations are preserved: only new keys are added, and keys no
# longer present in the sources are reported rather than silently dropped.
#
#   ruby Scripts/generate_strings.rb
#
require 'json'

ROOT = File.expand_path('..', __dir__)

TARGETS = {
  'G6SensorKit'   => %w[G6SensorKit Common],
  'G6SensorKitUI' => %w[G6SensorKitUI]
}.freeze

# LocalizedString("key", comment: "note"), tolerating a value: argument and
# newlines between arguments.
PATTERN = /LocalizedString\(\s*"((?:[^"\\]|\\.)*)"(?:.*?comment:\s*"((?:[^"\\]|\\.)*)")?/m

def unescape(text)
  text.gsub('\\"', '"').gsub('\\n', "\n").gsub('\\\\', '\\')
end

TARGETS.each do |target, directories|
  found = {}

  directories.each do |directory|
    Dir.glob(File.join(ROOT, directory, '**', '*.swift')).sort.each do |file|
      File.read(file).scan(PATTERN) do |key, comment|
        next if key.nil? || key.empty?
        found[unescape(key)] ||= comment && unescape(comment)
      end
    end
  end

  path = File.join(ROOT, target, 'Localizable.xcstrings')
  catalog =
    if File.exist?(path)
      JSON.parse(File.read(path))
    else
      { 'sourceLanguage' => 'en', 'strings' => {}, 'version' => '1.0' }
    end

  strings = catalog['strings'] ||= {}
  added = 0

  found.each do |key, comment|
    entry = strings[key]
    if entry.nil?
      entry = { 'extractionState' => 'manual' }
      strings[key] = entry
      added += 1
    end
    entry['comment'] = comment if comment && !comment.empty?
  end

  stale = strings.keys - found.keys

  File.write(path, JSON.pretty_generate(catalog) + "\n")

  puts "#{target}: #{found.count} strings (#{added} new)"
  puts "  no longer in sources: #{stale.join(', ')}" unless stale.empty?
end
