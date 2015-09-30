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


  def evaluate_classifier
    puts "Evaluating classifier"
    titles.evaluate_classifier(Classifier.new)
  end


  def classify
    puts "Classifying records"
    titles.classify(classifier)
  end


  def read_manual_titles_xls
    puts "Reading manually processed titles from in/titles_manual.xls"
    book = Spreadsheet.open 'in/titles_manual.xls'
    worksheet = book.worksheet 'Корректировка'
    fields_inv = ManualTitle::FIELDS.invert
    headers = worksheet.row(0).map do |h|
      fail "Unknown header: #{h}" unless fields_inv.key?(h)
      fields_inv[h]
    end
    count = 0
    worksheet.each 1 do |row|
      count += 1
      titles.add_manual_title Hash[headers.zip(row)]
    end
    puts "Manually processed titles read: #{count}"
  end


  def auto_width(column)
    w = column.drop(1).map{ |c| c.try(:length) }.compact.max
    return if w.nil?
    column.width = [5, [30, w].min].max
  end

  def write_titles_xls(titles, worksheet)
    worksheet.row(0).replace Title::FIELDS.values
    titles.each_with_index do |title, i|
      worksheet.row(i + 1).replace title.to_row
    end
    (0...Title::FIELDS.length).each { |i| auto_width(worksheet.column(i)) }
  end

  def write_xls
    puts 'Writing out/records.xls'
    book = Spreadsheet::Workbook.new

    records = book.create_worksheet :name => 'Все записи'
    write_titles_xls(titles, records)

    # titles
    #   .group_by(&:author_stat)
    #   .to_a.sort_by(&:first)
    #   .each do |author_stat, titles|
    #     sheet = book.create_worksheet :name => author_stat.to_s
    #     write_titles_xls(titles, sheet)
    #   end


    titles.invalid_titles.group_by(&:warning_class).sort_by(&:first)
      .each do |wc, titles|
        invalid_records = book.create_worksheet :name => "Проблемные записи #{wc}"
        write_titles_xls(titles, invalid_records)
      end

    categories = book.create_worksheet :name => 'Отрасли производства'
    categories.row(0).replace ['Номер', 'Отрасль', 'Кол-во записей']
    titles.categories_stats.each_with_index do |cat_count, i|
      category, count = cat_count
      categories.row(i + 1).replace(
        [category.number, category.title, count]
      )
    end
    auto_width(categories.column(1))

    authors = book.create_worksheet :name => 'Авторы'
    authors.row(0).replace ['Кол-во авторов', 'Кол-во записей']
    author_stats = titles.each_with_object(Hash.new(0)) do |title, c|
      c[title.author_stat] += 1
    end
    author_stats.to_a.sort_by(&:second).reverse
      .each_with_index do |author_stat, i|
        author, count = author_stat
        authors.row(i + 1).replace(
          [author, count]
        )
      end
    auto_width(authors.column(0))
    book.write 'out/records.xls'
  end


  def write_xls_final
    puts 'Writing out/records_final.xls'
    book = Spreadsheet::Workbook.new

    records = book.create_worksheet :name => 'Все записи'

    records.row(0).replace Title::FINAL_FIELDS.values

    row_num = 1
    titles.each do |title|
      title.final_rows.each do |row|
        records.row(row_num).replace row
        row_num += 1
      end
    end

    (0...Title::FIELDS.length).each { |i| auto_width(records.column(i)) }

    book.write 'out/records_final.xls'
  end


  def write_yaml_with_warnings
    File.write(
      'out/records_with_warnings.yml',
      titles.invalid_titles
        .select{ |t| t.warnings.include? "Name contains unknown tokens" }
        .select do |t|
          t.authors.flat_map(&:unknown_tokens).map(&:matched)
            .any?{ |w| w.match(/^(привилег)/i) }
        end
        .map(&:to_spec).to_yaml
    )
  end

  def write_yaml_by_author_stat
    titles.group_by(&:author_stat).each do |author_stat, titles|
      filepath = "out/records_#{author_stat}.yml"
      puts "Writing #{filepath}"
      File.write(filepath, titles.map(&:to_spec).to_yaml)
    end
  end

  def write_specs(title_codes)
    File.write(
      'out/record_specs.yaml',
      title_codes
        .flat_map{ |code| titles.select{ |t| t.code == code } }
        .map(&:to_spec).to_yaml
    )
  end

  def write_spec_sample(seed)
    s = titles
              .sample(100, random: Random.new(seed))
              .map(&:to_spec)
    File.write('out/record_spec_sample.yaml', s.to_yaml)
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

  def print_warnings
    w_count = titles.invalid_titles.flat_map(&:warnings)
      .each_with_object(Hash.new(0)) { |w, h| h[w] += 1 }

    c_count = titles.invalid_titles.flat_map(&:warning_class)
      .each_with_object(Hash.new(0)) { |w, h| h[w] += 1 }

    print_count w_count
    print_count c_count


    puts "Total titles with warnings: #{titles.invalid_titles.count}"
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

    # prefix_counts = titles.invalid_titles
    #   .reject(&:is_manual)
    #   .flat_map(&:authors).reject(&:person?)
    #   .map{ |c|
    #     prefix = c.unknown_tokens_with_type.map(&:matched).join('')
    #     prefix = Unicode::downcase(prefix)
    #     prefix.sub(/^«/, '').strip
    #   }
    #   .reject(&:empty?)
    #   .each_with_object(Hash.new(0)) { |w, c| c[w] += 1}

    # print_count prefix_counts

    # unknown_tokens = titles
    #     .flat_map{ |t|
    #       t.authors.flat_map{ |a|
    #         a.unknown_tokens
    #       }
    #     }

    # stemmer = Lingua::Stemmer.new(:language => "ru")
    # count = unknown_tokens
    #   .map(&:matched)
    #   .map do |s|
    #     s.strip
    #       .sub(/^[\p{lu}&&[^И]]$/, '[Initial]')
    #       # .sub(/^\p{word}{3,}(ому|ой)$/i, '[Adjective]')
    #   end
    #   .map { |w| stemmer.stem(Unicode.downcase(w)) }
    #   .each_with_object(Hash.new(0)) { |w, c| c[w] += 1}

    # print_count count

    location_count = titles.flat_map(&:location)
      .reject{ |l| l.match('губерния') }
      .each_with_object(Hash.new(0)) { |w, c| c[w] += 1}
    print_count location_count, :all

  end

  def print_token_stats
    total = 0
    unknown = 0
    titles.each do |title|
      types = title.subject_tokens.collect(&:type)
      next if types.include? :connector
      next if types.include? :open_quote
      next if types.include? :close_quote
      total += 1
      next unless types.include?(:punct) || types.include?(:word)
      unknown += 1
      puts
      puts title.subject
      puts title.subject_tokens.map(&:to_yaml)
    end
    puts "#{unknown}/#{total}"
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

  def print_count(count, limit = 25)
    limit = count.length if limit == :all
    count.to_a.sort_by(&:second).reverse.take(limit)
      .each { |t, v| puts [t, v].join(': ') }

    count = count.flat_map(&:second).count
    puts "Total: #{count}"
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
  "РГИА. Ф. 24. Оп. 6. Д. 1016",
  "РГИА. Ф. 24. Оп. 6. Д. 644",
  "РГИА. Ф. 24. Оп. 11. Д. 909",
  "РГИА. Ф. 24. Оп. 7. Д. 256",
  "РГИА. Ф. 24. Оп. 11. Д. 532",
  "РГИА. Ф. 24. Оп. 7. Д. 36",
  "РГИА. Ф. 24. Оп. 7. Д. 410",
  "РГИА. Ф. 24. Оп. 4. Д. 196",
  "РГИА. Ф. 24. Оп. 14. Д. 560",
  "РГИА. Ф. 24. Оп. 7. Д. 1332",
  "РГИА. Ф. 24. Оп. 7. Д. 1348",
  "РГИА. Ф. 24. Оп. 11. Д. 646",
  "РГИА. Ф. 24. Оп. 7. Д. 239",
  "РГИА. Ф. 24. Оп. 11. Д. 784",
  "РГИА. Ф. 24. Оп. 4. Д. 484",
  "РГИА. Ф. 24. Оп.4. Д. 882",
  "РГИА. Ф. 24. Оп. 7. Д. 242",
  "РГИА. Ф. 24. Оп. 7. Д. 329",
  "РГИА. Ф. 24. Оп. 8. Д. 883",
  "РГИА. Ф. 24. Оп. 12. Д. 947",
  "РГИА. Ф. 24. Оп. 12. Д. 962",
  "РГИА. Ф. 24. Оп. 7. Д. 113",
  "РГИА. Ф. 24. Оп. 5. Д. 498",
]


parser = Parser.new()
parser.read_classifier_categories
parser.read_classifier_examples
parser.read_titles()
parser.write_specs(spec_titles)
parser.read_manual_titles_xls()
parser.evaluate_classifier
parser.classify

# parser.write_spec_sample(666)
parser.write_xls
# parser.write_yaml_with_warnings
parser.write_xls_final
parser.print_warnings
# parser.print_citizenship_stats
# parser.write_yaml_by_author_stat
# parser.print_subject_stats
# parser.print_company_stats
# parser.print_title_stats
# parser.write_classifier_examples(5000)
# parser.print_token_stats
# parser.print_author_stats
# parser.print_stats
