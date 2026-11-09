# frozen_string_literal: true

module OpenspecPulse
  # Turns a change's tasks.md into groups and tasks (spec: tasks-parsing).
  module TasksParser
    Task = Data.define(:id, :text, :done, :indent)

    Group = Data.define(:title, :tasks) do
      def done = tasks.count(&:done)
      def total = tasks.size
    end

    Result = Data.define(:groups, :tasks_file) do
      def done = groups.sum(&:done)
      def total = groups.sum(&:total)
    end

    HEADING = /\A## (?<title>.*)\z/
    TASK = /\A(?<lead>[ \t]*)- \[(?<box>[ xX])\] (?<rest>.*)\z/
    ID = /\A(?<id>\d+(?:\.\d+)+)(?: (?<text>.*)|\z)/

    module_function

    def parse_file(path)
      return Result.new(groups: [], tasks_file: false) unless File.exist?(path)

      parse(File.read(path, encoding: "UTF-8"))
    end

    def parse(text)
      groups = []
      text.each_line(chomp: true) do |line|
        if (heading = HEADING.match(line))
          groups << Group.new(title: heading[:title].strip, tasks: [])
        elsif (task = TASK.match(line))
          groups << Group.new(title: "", tasks: []) if groups.empty?
          groups.last.tasks << build_task(task)
        end
      end
      Result.new(groups:, tasks_file: true)
    end

    def build_task(match)
      rest = match[:rest]
      id_match = ID.match(rest)
      id, text = id_match ? [id_match[:id], id_match[:text].to_s] : [nil, rest]
      indent = match[:lead].gsub("\t", "  ").length / 2
      Task.new(id:, text:, done: match[:box] != " ", indent:)
    end
  end
end
