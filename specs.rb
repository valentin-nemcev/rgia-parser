#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'

require 'minitest/autorun'
require 'yaml'

require_relative 'titles'



class CompleteTest < Minitest::Test
  specs = YAML.load_file('record_specs.yaml')

  specs.each_with_index do |s, i|
    input, output = s.values_at(:input, :output)

    define_method("test_record_#{i}") do
      title = ::Title.new.tap{ |t| input.each_line{ |l| t.parse_line(l) } }
      assert_equal output.to_yaml, title.to_spec[:output].to_yaml
    end
  end

end
