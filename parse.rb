#!/usr/bin/ruby

require 'rubygems'
require 'bundler/setup'

require 'active_support'
require 'active_support/core_ext'

require 'set'


class Title

  FIELD_SEPARATOR = ';~ '

  FIELDS = ActiveSupport::OrderedHash[
    :author_name        , 'Имя автора изобретения',
    :author_patronymic  , 'Отчество автора изобретения',
    :author_surname     , 'Фамилия автора изобретения',
    :author_initials    , 'Инициалы автора изобретения',
    :trustee_name       , 'Имя доверенного лица',
    :trustee_patronymic , 'Отчество доверенного лица',
    :trustee_surname    , 'Фамилия доверенного лица',
    :trustee_initials   , 'Инициалы доверенного лица',
    :title              , 'Заголовок',
    :cert_num           , '№ свидетельства',
    :date_range         , 'Крайние даты',
    :end_date           , 'Дата окончания',
    :code               , 'Архивный шифр',
    :notes              , 'Замечания',
    :topics             , 'Классификаторы',
  ]


  REQUIRED_FIELDS =
    [:author_name, :author_surname, :title, :end_date, :code].to_set

  FIELDS.keys.map do |field|
    attr_reader field
  end


  def initialize
    @lines = []
  end

  def parse_line(line)
    @lines << line
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


  def end_date
    dates[:end_date]
  end


  DATES_REGEX = /
    (?<range>
      \d+ \s+ \p{Alpha}+ \s+ \d+
      .*?
      \d+ \s+ \p{Alpha}+ \s+ (?<end_date>\d+)
    )
  /xi
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


  def record_str
    # parse
    FIELDS.keys.map do |field|
      send field
    end.join(FIELD_SEPARATOR) + FIELD_SEPARATOR
  end

end


class Titles

  include Enumerable
  extend Forwardable
  def_delegators :@titles, :each, :to_a

  def initialize
    @titles = []
    @current_title = nil
  end


  TITLE_START_REGEXP = Regexp.new('^дело', Regexp::IGNORECASE)

  def parse_line(line)
    line.strip!
    return if line.blank?

    if TITLE_START_REGEXP.match(line)
      @current_title = Title.new
      @titles << @current_title
    end
    @current_title.parse_line(line)
  end
end


Dir.glob('in/*') do |in_filepath|
  basename = File.basename in_filepath, '.*'
  int_txt_filepath = 'int/' + basename + '.txt'
  unless File.exists?(int_txt_filepath) && File.mtime(in_filepath) < File.mtime(int_txt_filepath)
    cmd = [
      "unrtf --html '#{in_filepath}'",
      "sed 's/<br>/<p>/g'",
      "pandoc -f html -t plain --no-wrap"
    ].join(' | ')
    puts "Converting #{in_filepath} to #{int_txt_filepath}"
    puts cmd
    File.write(int_txt_filepath, IO.popen(cmd).read)
  end

  titles = Titles.new
  File.open(int_txt_filepath).each do |line|
    titles.parse_line line
  end
  titles.each do |title|
    puts title.full_str
    p title.record_str
    puts
  end
  break
end
