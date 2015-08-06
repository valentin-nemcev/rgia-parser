#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'

require 'yaml'
require 'spreadsheet'

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


  def write_xls
    book = Spreadsheet::Workbook.new
    records = book.create_worksheet :name => 'Все записи'
    records.row(0).replace Title::FIELDS.keys.map(&:to_s)
    records.row(1).replace Title::FIELDS.values
    titles.each_with_index do |title, i|
      records.row(i + 2).replace title.to_row
    end
    book.write 'out/records.xls'
  end


  def write_yaml
    File.write('out/records.yml', titles.map(&:to_spec).to_yaml)
    # print_warnings(warnings)
  end

  def write_yaml_by_author_stat
    titles.group_by(&:author_stat).each do |author_stat, titles|
      filepath = "out/records_#{author_stat}.yml"
      puts "Writing #{filepath}"
      File.write(filepath, titles.map(&:to_spec).to_yaml)
    end
  end

  def write_specs(title_codes)
    File.write('out/record_specs.yaml',
               titles.values_at(*title_codes).map(&:to_spec).to_yaml)
  end

  def write_classifier_examples(n)
    out_txt_categories_filepath = 'out/records_categories_worst.txt'
    File.open(out_txt_categories_filepath, 'w') do |out_file|
      # titles.with_worst_category_scores(n).each do |title|
      titles.select(&:needs_classification?).sample(n).each do |title|
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

  def print_title_stats
    without_title = titles.invalid_titles.select do |t|
      t.warnings.include? "Missing title"
    end

    titles = without_title.map do |title|
      title.lines.first[/^((\p{Alpha}{,2}\s+)?\p{Alpha}+)/, 1]
    end
    count = titles.each_with_object(Hash.new(0)) { |t, c| c[t] += 1}

    print_count count
  end

  def print_company_stats
    with_company = titles.select do |t|
      t.authors.empty?
    end


    words = with_company.flat_map do |title|
      title.subject.try{ |s| s.split(/[^\p{Alpha}]/)} || []
    end

    # words = with_company.map do |title|
    #   title.subject.try{ |s| s[ /\p{Alpha}{3,}/ ]}
    # end.compact


    stemmer = Lingua::Stemmer.new(:language => "ru")
    count = words
      .select{ |w| w.length > 3 }
      .map { |w| stemmer.stem(Unicode.downcase(w)) }
      .each_with_object(Hash.new(0)) { |w, c| c[w] += 1}

    print_count count
  end


  def print_subject_stats
    singles = []
    pairs = []
    triples = []
    stemmer = Lingua::Stemmer.new(:language => "ru")
    puts 'Fully parsed: ' +
      titles.map(&:stripped_subject).select(&:blank?).count.to_s
    puts 'Unparsed without company: ' +
      titles.select{ |t| t.company_name.blank? && t.stripped_subject.present? }
        .each{ |t| 
          # puts t.subject; puts t.stripped_subject 
        }
        .count.to_s
    titles.select{ |t| t.company_name.blank? }.each do |title|
      words = (title.stripped_subject.try{ |s| s.split(/[^\p{alnum}]/)} || [])
        .select{ |w| w.length > 1 }
        .map { |w| stemmer.stem(Unicode.downcase(w)) }
      # if words.include? 'электрическ'
      if words.include?('американск')
        puts title.subject
      end
      singles.push(*words)
      pairs.push(*words.each_cons(2).map{ |c| c.join(' ')})
      triples.push(*words.each_cons(3).map{ |c| c.join(' ')})
      # pairs.push(*words.each_cons(2).select{|c| c.include? 'крестьянин'}.map{ |c| c.join(' ')})
      # triples.push(*words.each_cons(3).select{|c| c.include? 'крестьянин'}.map{ |c| c.join(' ')})
    end


    count = Hash.new(0)
    singles.each { |w| count[w] += 1}
    pairs.each { |w| count[w] += 1}
    triples.each { |w| count[w] += 1}

    print_count count
  end

  def print_author_stats
    count = titles.each_with_object(Hash.new(0)) do |title, c|
      c[title.author_stat] += 1
    end

    print_count count
  end


  def print_citizenship_stats
    # without_citizenship = titles.invalid_titles.select do |t|
    #   t.warnings.include? "Unknown citizenship"
    # end
    count = titles.each_with_object(Hash.new(0)) do |title, c|
      m = /(?<citizenship>[\p{Alpha}-]+)\s+(поддан|гражд)/i.match(title.subject)
      stemmer = Lingua::Stemmer.new(:language => "ru")
      if m.present?
        c[stemmer.stem(m[:citizenship])] += 1
      else
        c['unknown'] += 1
      end
    end
    print_count count
  end

  def print_count(count)
    count.to_a.sort_by(&:second).reverse.take(50)
      .each { |t, v| puts [t, v].join(': ') }
  end
end


spec_titles = [
  "РГИА. Ф. 24. Оп. 6. Д. 1368",
  "РГИА. Ф. 24. Оп. 8. Д. 1523",
  "РГИА. Ф. 24. Оп. 5. Д. 453",
  "РГИА. Ф. 24. Оп. 7. Д. 236",
  "РГИА. Ф. 24. Оп. 4. Д. 552",
  "РГИА. Ф. 24. Оп. 5. Д. 885",
  "РГИА. Ф. 24. Оп. 14. Д. 770",
  "РГИА. Ф. 24. Оп. 4. Д. 58",
  "РГИА. Ф. 24. Оп. 7. Д. 515",
  "РГИА. Ф. 24. Оп. 6. Д. 189",
]

parser = Parser.new()
parser.read_classifier_categories
parser.read_classifier_examples
parser.train_classifier
parser.read_titles()
parser.write_specs(spec_titles)
# parser.classify
# parser.write_xls
# parser.print_citizenship_stats
# parser.write_yaml_by_author_stat
# parser.print_subject_stats
# parser.print_company_stats
# parser.print_title_stats
# parser.write_classifier_examples(3000)
parser.print_stats
