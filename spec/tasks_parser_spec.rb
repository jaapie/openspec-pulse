# frozen_string_literal: true

require "openspec_pulse/tasks_parser"

RSpec.describe OpenspecPulse::TasksParser do
  FIXTURES = File.expand_path("fixtures/tasks", __dir__)

  def parse(text) = described_class.parse(text)
  def fixture(name) = described_class.parse_file(File.join(FIXTURES, "#{name}.md"))

  def only_task(line) = parse(line).groups.first.tasks.first

  describe "groups (4.2)" do
    it "takes each ## heading's full text as a group title" do
      titles = fixture("out-of-order-groups").groups.map(&:title)
      expect(titles.first)
        .to eq("1. Group 1 title — DONE 2026-08-06")
    end

    it "keeps groups in file order, not numeric order" do
      numbers = fixture("out-of-order-groups").groups.map { |g| g.title[/\A\d+/] }
      expect(numbers).to eq(%w[1 2 5 3 4 6 7])
    end

    it "keeps a heading with no tasks as an empty group" do
      moved = fixture("out-of-order-groups").groups.find { |g| g.title.start_with?("6.") }
      expect(moved.tasks).to eq([])
    end

    it "puts tasks before the first heading in a group with an empty title" do
      groups = fixture("edge-cases").groups
      expect(groups.first.title).to eq("")
      expect(groups.first.tasks.map(&:text)).to eq(["tidy up"])
    end

    it "does not add an untitled group when no task comes before the first heading" do
      expect(fixture("notes-and-sub-bullets").groups.first.title).to eq("1. Group 1 title")
    end

    it "does not start a group at a ### heading" do
      groups = fixture("edge-cases").groups
      expect(groups.map(&:title)).to eq(["", "1. Edge cases"])
      expect(groups.last.tasks.last.id).to eq("1.4")
    end
  end

  describe "task lines (4.3)" do
    it "reads - [ ] as an open task" do
      task = only_task("- [ ] 7.1 Write failing test")
      expect(task.done).to be(false)
    end

    it "reads - [x] and - [X] as done" do
      expect(only_task("- [x] 1.2 Something").done).to be(true)
      expect(only_task("- [X] 1.2 Something").done).to be(true)
    end

    it "ignores ordinary bullets and near-miss checkboxes" do
      text = "- 04 Nov 2026: notes about src/auth.js\n-[ ] no space\n- [ ]no space after\n* [ ] star bullet\n"
      expect(parse(text).total).to eq(0)
    end

    it "takes a dotted number as the id and leaves it out of the text" do
      task = only_task("- [ ] 7.10 Re-check consumers")
      expect(task.id).to eq("7.10")
      expect(task.text).to eq("Re-check consumers")
    end

    it "gives a null id when the text has no dotted number" do
      task = only_task("- [ ] Re-check consumers")
      expect(task.id).to be_nil
      expect(task.text).to eq("Re-check consumers")
    end

    it "does not take a plain number or a date as an id" do
      expect(only_task("- [ ] 2026 retrospective").id).to be_nil
      expect(only_task("- [ ] 4.1.x is not an id").id).to be_nil
    end

    it "keeps long text whole, including inline markdown" do
      long = "Check `config.js` " + ("and more " * 70)
      task = only_task("- [ ] 3.7 #{long}")
      expect(task.text).to eq(long)
      expect(task.text.length).to be > 600
    end

    it "sets indent from leading spaces, two per level, tabs as two spaces" do
      indents = fixture("edge-cases").groups.last.tasks.to_h { |t| [t.text, t.indent] }
      expect(indents).to include(
        "Capital X counts as done" => 0,
        "sub-step" => 1,
        "sub-sub-step" => 2,
        "tab-indented sub-step" => 1
      )
    end

    it "does not let a notes paragraph end the group" do
      group = fixture("edge-cases").groups.last
      expect(group.tasks.map(&:id)).to include("1.2", "1.3", "1.4")
      expect(group.tasks.map(&:text).join).not_to include("Notes")
    end

    it "does not treat indented note bullets as tasks" do
      group = fixture("notes-and-sub-bullets").groups.first
      expect(group.tasks.map(&:id)).to eq(%w[1.1 1.2 1.3 1.4 1.5 1.6])
    end
  end

  describe "counts (4.4)" do
    it "counts done and total per group" do
      group = fixture("out-of-order-groups").groups.find { |g| g.title.start_with?("2.") }
      expect([group.done, group.total]).to eq([8, 8])
    end

    it "counts done and total for the whole change" do
      result = fixture("edge-cases")
      expect([result.done, result.total]).to eq([3, 9])
    end

    it "marks a parsed file as tasks_file true" do
      expect(fixture("edge-cases").tasks_file).to be(true)
    end

    it "gives no groups, zero counts and tasks_file false when tasks.md is missing" do
      result = described_class.parse_file(File.join(FIXTURES, "no-such-file.md"))
      expect(result.groups).to eq([])
      expect([result.done, result.total]).to eq([0, 0])
      expect(result.tasks_file).to be(false)
    end
  end

  # The two shape fixtures keep the structure of two real tasks.md files with
  # the prose replaced, so these counts are what OpenSpec reported for them.
  describe "agreement with openspec list --json (4.5)" do
    {
      "out-of-order-groups" => [29, 39],
      "notes-and-sub-bullets" => [33, 37]
    }.each do |name, counts|
      it "matches OpenSpec's #{counts.join('/')} for #{name}" do
        result = fixture(name)
        expect([result.done, result.total]).to eq(counts)
      end
    end
  end
end
