#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'

require 'yaml'

require 'active_support'
require 'active_support/core_ext'

require 'stuff-classifier'

require 'parallel'
require 'ruby-progressbar'

require 'set'

require_relative 'classifier'
require_relative 'titles'



class Parser

  attr_reader :titles, :classifier

  def initialize
    @classifier = Classifier.new
    @titles = Titles.new()
  end


  def cache_stale?(input, cache)
    !File.exists?(cache) || File.mtime(input) >= File.mtime(cache)
  end


  def in_txt_filepaths
    @in_txt_filepaths ||= Dir.glob('in/*.rtf').map do |in_filepath|
      basename = File.basename in_filepath, '.*'
      in_txt_filepath = 'int/' + basename + '.txt'
      if cache_stale?(in_filepath, in_txt_filepath)
        cmd = [
          "unrtf --html '#{in_filepath}'",
          "sed 's/<br>/<p>/g'",
          "pandoc -f html -t plain --no-wrap"
        ].join(' | ')
        puts "Converting #{in_filepath} to #{in_txt_filepath}"
        File.write(in_txt_filepath, IO.popen(cmd).read)
      end
      in_txt_filepath
    end
  end


  def merge_files(in_filepaths, merged_filepath)
    merged_is_stale = in_filepaths.any? do |in_txt_filepath|
      cache_stale?(in_txt_filepath, merged_filepath)
    end

    if merged_is_stale
      puts "Merging #{merged_filepath}"
      args = in_filepaths.map{ |p| "'#{p}'" }.join(' ')
      system("cat #{args} > #{merged_filepath}")
    end

    merged_filepath
  end


  def convert_classifier_examples
    Dir.glob('in_classifier/examples*.rtf').map do |in_filepath|
      basename = File.basename in_filepath, '.*'
      in_txt_filepath = 'int/' + basename + '.txt'
      if cache_stale?(in_filepath, in_txt_filepath)
        cmd = [
          "unrtf --html '#{in_filepath}'",
          "sed 's/<br>/<p>/g'",
          "pandoc -f html -t plain --no-wrap"
        ].join(' | ')
        puts "Converting #{in_filepath} to #{in_txt_filepath}"
        File.write(in_txt_filepath, IO.popen(cmd).read)
      end
      in_txt_filepath
    end
  end


  def in_merged_txt_filepath
    @in_merged_txt_filepath ||= merge_files(in_txt_filepaths, 'int/records.txt')
  end


  def in_txt_classifier_examples_filepaths
    @in_txt_classifier_examples_filepaths ||= convert_classifier_examples
  end


  def in_merged_classifier_examples_filepath
    @in_merged_classifier_examples_filepath ||=
      merge_files(in_txt_classifier_examples_filepaths, 'int/classifier_examples.txt')
  end


  def read_titles(limit=nil)
    puts "Reading titles from #{in_merged_txt_filepath}"
    File.open(in_merged_txt_filepath).each do |line|
      titles.parse_line line
      break if limit.present? && titles.size > limit
    end
    puts "Total titles #{titles.size}"
  end


  def read_classifier_categories
    in_filepath = 'in_classifier/categories.txt'
    puts "Reading classifier categories from #{in_filepath}"
    File.readlines(in_filepath).each do |line|
      next if line.blank?
      titles.parse_category_line(line)
    end
    puts "Total categories #{titles.classifier_categories.size}"
  end


  def read_classifier_examples
    puts "Reading classifier examples from #{in_merged_classifier_examples_filepath}"
    File.open(in_merged_classifier_examples_filepath).each do |line|
      titles.parse_classifier_example_line line
    end
    puts "Total classifier examples #{titles.classifier_examples.size}"
    with_categories = titles.classifier_examples.select(&:category)
    puts "Classifier examples with categories #{with_categories.size}"
  end


  def train_classifier
    classifier.train(titles.classifier_examples)
  end


  def classify
    puts "Classifying records"
    titles.classify(classifier)
  end


  def write_records
    show_warnings = true

    out_txt_filepath = 'out/records.txt'
    out_txt_invalid_filepath = 'out/records_invalid.txt'

    warnings = []
    out_invalid_file = File.open(out_txt_invalid_filepath, 'w')
    out_file = File.open(out_txt_filepath, 'w')

    titles.each do |title|
      out_file.puts title.record_str_debug
      out_file.puts
      next if title.valid?
      if show_warnings
        out_invalid_file.puts title.full_str
        out_invalid_file.puts title.warnings
        out_invalid_file.puts
      end
      warnings.push(*title.warnings)
    end

    print_warnings(warnings)
  end

  def write_specs(title_codes)
    File.write('out/record_specs.yaml', title_codes.map do |code|
      titles[code].to_spec
    end.to_yaml)
  end

  def write_classifier_examples(n)
    out_txt_categories_filepath = 'out/records_categories_worst.txt'
    File.open(out_txt_categories_filepath, 'w') do |out_file|
      titles.with_worst_category_scores(n).each do |title|
        next if title.object.blank?
        out_file.puts title.code
        out_file.puts title.object
        out_file.puts title.categories.take(2).join("\n")
        out_file.puts #title.categories.join('; ')
        out_file.puts
      end
    end
  end

  def print_warnings(warnings)
    warnings
      .each_with_object(Hash.new(0)) { |w, h| h[w] += 1 }
      .each { |w, count| puts [w, count].join(': ') }
  end

  def print_stats
    titles.stats.each { |t, v| puts [t, v].join(': ') }
  end
end


spec_titles = [
  "РГИА. Ф. 24. Оп. 6. Д. 1368",
  "РГИА. Ф. 24. Оп. 8. Д. 1523"
]

parser = Parser.new()
# parser.read_classifier_categories
# parser.read_classifier_examples
# parser.train_classifier
parser.read_titles()
parser.write_specs(spec_titles)
# parser.classify
# parser.write_records
# parser.write_classifier_examples(3000)
parser.print_stats
