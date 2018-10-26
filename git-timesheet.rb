#!/usr/bin/env ruby

# Avoid encoding error in Ruby 1.9 when system locale does not match Git encoding
# Binary encoding should probably work regardless of the underlying locale
Encoding.default_external='binary' if defined?(Encoding)

require 'optparse'
require 'time'

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: git-timesheet [options]"

  opts.on("-s", "--since [TIME]", "Start date for the report (default is 1 week ago)") do |time|
    options[:since] = time
  end
  
  opts.on("-a", "--author [EMAIL]", "User for the report (default is the author set in git config)") do |author|
    options[:author] = author
  end

  opts.on(nil, '--authors', 'List all available authors') do |authors|
    options[:authors] = authors
  end

  opts.on('-h', '--hour', 'The hour when the work day starts') do |hour|
    options[:hour] = hour.to_i
  end
end.parse!

options[:since] ||= '1 week ago'
options[:hour] ||= 8

class Day
  def initialize
    @commits = []
  end
  
  def <<(commit)
    @commits << commit
  end

  def commits
    @commits.sort do |a, b|
      a.timestamp <=> b.timestamp
    end
  end
  
  def duration
    # Minimum is 30 min
    [commits.last.timestamp - commits.first.timestamp, 30*60].max
  end
  
  def hours_string
    "%02d:%02d" % [duration/3600%24, duration/60%60]
  end
end

Struct.new("Commit", :timestamp, :message)

if options[:authors]
  authors = `git log --no-merges --simplify-merges --format="%an (%ae)" --since="#{options[:since].gsub('"','\\"')}"`.strip.split("\n").uniq
  puts authors.join("\n")
else
  options[:author] ||= `git config --get user.email`.strip
  log_lines = `git log --all --no-merges --simplify-merges --author="#{options[:author].gsub('"','\\"')}" --format="%ad %s" --date=iso --since="#{options[:since].gsub('"','\\"')}"`.split("\n")
  day_entries = log_lines.inject({}) {|days, line|
    timestamp = Time.parse line.slice(0,25)
    message = line[26..-1]
    commit = Struct::Commit.new(timestamp, message)
    day_string = (timestamp.hour < options[:hour] ? timestamp-24*60*60 : timestamp).strftime("%Y-%m-%d")
    days[day_string] ||= Day.new
    days[day_string] << commit
    days
  }.sort{|a,b| a[0]<=>b[0]}
  
  day_entries.each do |day_string, day|
    puts "# #{day_string} - #{day.hours_string}"
    day.commits.each do |commit|
      puts "#{commit.timestamp} #{commit.message}"
    end
  end
  
  first_day = Time.parse(day_entries.first[0])
  last_day = Time.parse(day_entries.last[0])
  days = (last_day-first_day) / (24*60*60)
  hours = day_entries.map { |day_string, day|
    day.duration / (60*60)
  }.sum
  puts
  puts "Average hours/week: #{7 * hours/days}"
end
