#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'

require 'active_support'
require 'active_support/core_ext'

require 'set'


class Title

  def warnings
    @warnings = []
    validate
    @warnings
  end

  def warn(msg)
    @warnings << msg
    self
  end

  FIELD_SEPARATOR = ';~ '
  TAG_SEPARATOR = ',~ '

  FIELDS = ActiveSupport::OrderedHash[
    :author_name        , 'Имя автора изобретения',
    :author_patronymic  , 'Отчество автора изобретения',
    :author             , 'Фамилия автора изобретения',
    :author_initials    , 'Инициалы автора изобретения',
    :trustee_name       , 'Имя доверенного лица',
    :trustee_patronymic , 'Отчество доверенного лица',
    :trustee_surname    , 'Фамилия доверенного лица',
    :trustee_initials   , 'Инициалы доверенного лица',
    :title              , 'Заголовок',
    :cert_num           , '№ свидетельства',
    :date_range         , 'Крайние даты',
    :end_year           , 'Дата окончания',
    :code               , 'Архивный шифр',
    :notes              , 'Замечания',
    :tags_str           , 'Классификаторы',
  ]


  REQUIRED_FIELDS =
    [:title, :code].to_set
  # REQUIRED_FIELDS =
  #   [:author_name, :author_surname, :title, :end_year, :code].to_set

  FIELDS.keys.map do |field|
    attr_reader field
  end


  attr_reader :lines

  def initialize
    @lines = []
  end

  def parse_line(line)
    @lines << line
  end


  def tags_str
    tags.join(TAG_SEPARATOR)
  end

  def tags
    citizenship
  end

  CODE_REGEX = /ргиа .*? $/xi
  def code
    CODE_REGEX.match(full_str) do |m|
      return m[0].sub(/[\s.]*$/, '')
    end
  end


  def date_range
    dates[:range]
  end


  def end_year
    dates[:end_year]
  end


  DATES_REGEX = /
    ^\s*
    (?<range>
      (\d+ \s* \p{Alpha}+ \s* \d+)?
      .*?
      (\d+ \s* \p{Alpha}+ \s*)? (?<end_year>\d{4})
    )
    [\s.]*
    $
  /xui
  def dates
    DATES_REGEX.match(full_str) || {}
  end


  def cert_num
    cert_num_parens
  end


  CERT_NUM_PARENS_REGEX = /
    \(\s* привилегия .*? (\d+) \)[\s.]*
  /xi

  def cert_num_parens
    CERT_NUM_PARENS_REGEX.match(full_str) do |m|
      return m[1]
    end
  end


  def author
    author_surname || subject
  end


  def author_initials
    [author_name, author_patronymic]
      .compact.map { |name| name[0, 1].upcase + '.' }
      .join(' ').tap { |initials| initials.blank? ? nil : initials }
  end

  def author_name
    parsed_author[:name]
  end

  def author_patronymic
    parsed_author[:patronymic]
  end

  def author_surname
    parsed_author[:surname]
  end


  PARSED_AUTHOR_REGEX = /
    ^
    (?<surname>\p{Lu}\p{Ll}+)
    \s+
    (?<name>\p{Lu}[\p{Ll}.]+)?
    \s*
    (?<patronymic>\p{Lu}[\p{Ll}.]+)?
    $
  /x
  def parsed_author
    PARSED_AUTHOR_REGEX.match(subject) || {}
  end



  CITIZENSHIP_REGEXP = /\s*(иностран\p{Alpha}+)\s+/i
  def citizenship
    CITIZENSHIP_REGEXP.match(parsed_title[:subject]) do |m|
      return ['Иностранец']
    end
    return ['Российский подданный']
  end

  def subject
    parsed_title[:subject].try do |subject|
      subject.sub(CITIZENSHIP_REGEXP, '')
    end
  end


  def object
    parsed_title[:object]
  end


  PARSED_TITLE_REGEX = /
    ^
    дело\sо\sвыдаче\sпривилегии\s
    (?<subject>.*?)
    \s(?:на|для)\s
    (?<object>.*?)
    $
  /xi

  def parsed_title
    PARSED_TITLE_REGEX.match(title) || {}
  end


  TITLE_REGEX = /(дело\sо\sвыдаче.*?)$/i

  def title
    TITLE_REGEX.match(full_str) do |m|
      title = m[1]
      title
        .sub(CERT_NUM_PARENS_REGEX, '')
        .sub(/[\s.]*$/, '')
    end
  end


  def full_str
    @full_str ||= @lines.join("\n").squeeze(' ')
  end


  def validate
    validate_required_fields_present
    validate_line_count
    validate_parsed_title
  end


  def validate_line_count
    warn "Suspicious line count" unless lines.count.in? 2..4
  end

  def validate_parsed_title
    warn "Can't parse title" if parsed_title.size == 0
  end


  def validate_required_fields_present
    REQUIRED_FIELDS.each do |field|
      if send(field).nil?
        warn "Missing #{field}"
      end
    end
  end


  def valid?
    warnings.empty?
  end


  def record_str
    FIELDS.keys.map do |field|
      send field
    end.join(FIELD_SEPARATOR) + FIELD_SEPARATOR
  end

  def record_str_debug
    [:title, :subject, :citizenship, :author, :author_name, :author_patronymic,
     :author_surname, :author_initials, :object].map do |field|
      value = send field
      next if value.nil?
      [field.to_s.ljust(12), value].join(': ')
    end.compact.join("\n")
  end

end



class Titles

  include Enumerable
  extend Forwardable
  def_delegators :@titles, :each, :to_a
  attr_reader :titles

  def initialize
    @titles = []
    @current_title = nil
  end


  TITLE_START_REGEXP = Regexp.new('^дело', Regexp::IGNORECASE)
  TITLE_END_REGEP = Regexp.new('^\s*ргиа', Regexp::IGNORECASE)

  def next_title
    @current_title = nil
  end

  def current_title
    @current_title ||= Title.new.tap { |t| @titles.push(t) }
  end

  def parse_line(line)
    line.strip!
    return if line.blank?

    # next_title if TITLE_START_REGEXP.match(line)
    current_title.parse_line(line)
    next_title if TITLE_END_REGEP.match(line)
  end

  def invalid_titles
    titles.reject(&:valid?)
  end

  def stats
    {
      "Total records" => titles.size,
      "Invalid records" => invalid_titles.size
    }
  end
end


show_warnings = true

total_stats = {}
total_warnings = []

def print_warnings(warnings)
  warnings
    .each_with_object(Hash.new(0)) { |w, h| h[w] += 1 }
    .each { |w, count| puts [w, count].join(': ') }
end

def print_stats(stats)
  stats.each { |t, v| puts [t, v].join(': ') }
end

Dir.glob('in/*.rtf') do |in_filepath|
  basename = File.basename in_filepath, '.*'
  in_txt_filepath = 'int/' + basename + '.txt'
  out_txt_filepath = 'out/' + basename + '.txt'
  puts "Processing #{in_filepath}"
  unless File.exists?(in_txt_filepath) && File.mtime(in_filepath) < File.mtime(in_txt_filepath)
    cmd = [
      "unrtf --html '#{in_filepath}'",
      "sed 's/<br>/<p>/g'",
      "pandoc -f html -t plain --no-wrap"
    ].join(' | ')
    puts "Converting #{in_filepath} to #{in_txt_filepath}"
    File.write(in_txt_filepath, IO.popen(cmd).read)
  end

  titles = Titles.new
  File.open(in_txt_filepath).each do |line|
    titles.parse_line line
  end

  warnings = []
  File.open(out_txt_filepath, 'w') do |out_file|
    titles.each do |title|
      out_file.puts title.full_str
      out_file.puts title.record_str
      out_file.puts
      next if title.valid?
      if show_warnings
        puts title.full_str
        # puts title.record_str
        puts title.warnings
        puts
      end
      warnings.push(*title.warnings)
    end
  end

  total_warnings.push(*warnings)
  print_warnings(warnings)

  stats = titles.stats
  total_stats.merge!(stats) { |t, v1, v2| v1 + v2 }
  print_stats(stats)
  puts
end

puts "Totals:"
print_warnings(total_warnings)
print_stats(total_stats)
