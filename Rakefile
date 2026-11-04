# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/*_test.rb"]
  t.warning = true
end

desc "Live smoke test against the real API (costs nothing)"
task :smoke do
  ruby "-Ilib script/smoke.rb"
end

task default: :test
