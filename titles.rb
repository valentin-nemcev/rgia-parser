require 'active_support'
require 'active_support/core_ext'

require 'memoist'

require 'strscan'

require 'lingua/stemmer'
require 'unicode'
require 'petrovich'

require_relative 'subject_tokenizer'
require_relative 'author_parser'


class MatchData

  def to_h
    Hash[names.map(&:to_sym).zip(captures) + [[:full, to_s]]]
  end

end


module Authors

  def author_stat
    author_count = 0
    company_count = 0
    authors.each do |a|
      if a.person?
        author_count += 1
      else
        company_count += 1
      end
    end
    "#{company_count + author_count} C#{company_count} A#{author_count}"
  end


  (1..5).each do |i|
    define_method("author#{i}") do
      authors[i - 1].try do |a|
        if a.person?
          a.full_name
        else
          'К: ' + a.full_name
        end
      end
    end
  end

end


module FinalFields

  FINAL_FIELDS = ActiveSupport::OrderedHash[
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

  AUTHOR_FINAL_FIELDS = [
    :author_name,
    :author_patronymic,
    :author,
    :author_initials,
  ]
  SKIP_FINAL_FIELS = [
    :trustee_name,
    :trustee_patronymic,
    :trustee_surname,
    :trustee_initials,
  ]

  TITLE_FINAL_FIELDS = [
    :title,
    :cert_num,
    :date_range,
    :end_year,
    :code,
    :notes,
    :tags_str,
  ]

  def notes
  end

  def tags_str
    ((category.try(:with_parents) || []).map(&:to_s) \
     + citizenship + position + occupation + location)
      .join(',~')
  end

  EMPTY_AUTHOR = Person.new()
  def final_rows
    authors = self.authors.present? ? self.authors : [EMPTY_AUTHOR]
    authors.map do |author|
      AUTHOR_FINAL_FIELDS.map{ |f| author.send(f) } +
        SKIP_FINAL_FIELS.map{ |f| nil } +
        TITLE_FINAL_FIELDS.map{ |f| self.send(f) }
    end
  end

end

require_relative 'manual_titles'

class Title

  extend Memoist



  # Source lines

  attr_reader :lines

  def initialize
    @lines = []
  end

  def parse_line(line)
    @lines << line
  end

  def full_str
    @full_str ||= @lines.join("\n").squeeze(' ')
  end
  memoize :full_str



  # Parsed title

  PARSED_TITLE_REGEXES = [
    /
      ^
      дело\sо\sвыдаче\s
      (привилегии[\p{p}\p{z}]+)?
      (?<duration>на\s\d+\s?(год|года|лет)\s)?
      (привилегии[\p{z}]+)?
      (?<subject>.*?)
      (\s|,|\.)(?:на)\s(?!\d+\s?(год|года|лет)\s)
      (?<object>.*?)
      (?<subject_company>
        [,\s]+передан\p{Alpha}+
        .*?
      )?
      $
    /xi,
    /
      ^
      по\sходатайству\s
      (?<subject>.*?)
      \s(?:о)\s
      (?<object>.*?)
      $
    /xi,
  ]

  NOT_PARSED_TITLE_REGEXES = [/[\p{p}\p{z}]то же[\p{p}\p{z}]/i]

  def parsed_title
    NOT_PARSED_TITLE_REGEXES.each do |regex|
      if regex.match(title)
        return {}
      end
    end
    PARSED_TITLE_REGEXES.each_with_index do |regex, i|
      m = regex.match(title)
      next if m.nil?
      return m.to_h.tap do |h|
        h[:subject] += h[:subject_company] if h[:subject_company].present?
        h[:irregular_title] if i > 0
      end
    end
    return {}
  end
  memoize :parsed_title

  def subject
    parsed_title[:subject]
  end

  def object
    parsed_title[:object].try{ |t| t.gsub(/s+/, ' ')}
  end
  memoize :object

  def irregular_title?
    parsed_title[:irregular_title]
  end

  def duration
    parsed_title[:duration].try{ |t| t.strip }
  end
  memoize :duration



  # Title, code, date & cert. num

  def title
    parsed_str[:title]
  end

  def code
    parsed_str[:code]
  end


  def date_range
    dates[:range]
  end

  def end_year
    dates[:end_year]
  end

  def dates
    parsed_str[:dates] || {}
  end

  def cert_num
    parsed_str[:cert_num]
  end


  DATES_REGEX = /
    ^\s*
    (?<range>
      (\d+ \s* \p{Alpha}+ \s* \d+)?
      [\p{P}\s]*?
      (\d+ \s* \p{Alpha}+ \s*)? (?<end_year>\d{4})
    )
    [\s.]*
    $
  /xui

  CODE_REGEX = /^(ргиа\.?\s*)?ф\.?\s*\d+ .*? $/xi

  CERT_NUM_PARENS_REGEX = /
    (?:\()? \s* (?:привилегия|патент) \s? [^\s]? \s? (\d+) \s* (?:\))?[\s.]*
  /xi

  def parsed_str
    result = {}
    str = full_str.clone

    str.gsub!(CODE_REGEX) do
      result[:code] = Regexp.last_match[0].sub(/[\s.]*$/, '')
      ''
    end

    str.gsub!(DATES_REGEX) do
      result[:dates] = Regexp.last_match.to_h
      ''
    end

    str.gsub!(CERT_NUM_PARENS_REGEX) do |m|
      result[:cert_num] = Regexp.last_match[1]
      ''
    end

    str.gsub!(/[\r\n\p{Z}]+/, ' ')
    str.gsub!(/[\s.]*$/, '')

    result[:title] = str

    return result
  end
  memoize :parsed_str



  # Subject parsing

  def subject_tokens
    SubjectTokenizer.new(parsed_title[:subject].to_s).tokenize
  end
  memoize :subject_tokens


  def authors
    AuthorParser.new(subject_tokens).parse
  end
  memoize :authors



  # Category

  def category=(cat)
    @category = cat
  end

  def category_s
    category.to_s
  end

  def category
    @category || classifier_category
  end

  def classifier_category
    categories.first
  end

  def classified_correctly?
    @category == classifier_category
  end

  def categories
    category_scores.map(&:second)
  end

  def category_scores
    @category_scores || []
  end

  def category_scores=(scores)
    @category_scores = scores.take(3).map do |category, score|
      [Math.log(score), category]
    end
  end

  def category_best_score
    category_scores.first[0]
  end

  def category_confidence_score
    scores = category_scores.take(2).map(&:first)
    scores.first - scores.last
  end
  memoize :category_confidence_score

  def needs_classification?
    @category.nil? && object.present?
  end



  # Tags

  def citizenship
    citizenship = authors.flat_map{ |a| a.tags_for(:citizenship) }.uniq.to_a
    if citizenship.empty?
      ['Российский подданный']
    else
      citizenship
    end
  end

  def citizenship_s
    citizenship.join(', ')
  end

  def occupation
    authors.flat_map{ |a| a.tags_for(:occupation) }.uniq.to_a
  end

  def occupation_s
    occupation.join(', ')
  end

  def position
    authors.flat_map{ |a| a.tags_for(:position) }.uniq.to_a
  end

  def position_s
    position.join(', ')
  end

  def location
    authors.flat_map{ |a| a.tags_for(:location) }.uniq.to_a
  end

  def location_s
    location.join(', ')
  end



  # Warnings

  def warnings
    if @warnings.nil?
      @warnings = []
      validate
    end
    @warnings
  end

  def warnings_s
    warnings.join(', ')
  end

  def warn(msg)
    warnings << msg
    warnings.uniq!
    self
  end

  def validate
    validate_line_count
    unless validate_parsed_title
      validate_subject_tokens
      validate_authors
    end
  end


  def validate_authors
    warn "Empty authors" if authors.empty? || authors.any?(&:empty?)
    authors.each do |author|
      author.validate(self)
    end
    # warn "Suspicious author count" if authors.count > 3
  end

  def validate_subject_tokens
    warn "Subject not fully parsed" if subject_tokens.detect{ |t| t.type == :rest }
    warn "Possible inflection problems" if irregular_title?
  end

  def validate_line_count
    # warn "Suspicious line count" unless lines.count.in? 2..4
  end

  def validate_parsed_title
    warn "Can't parse title" if title.present? && parsed_title.size == 0
  end


  A_CLASS = [
    "Empty authors",
    "Missing surname",
    "Can't parse title",
  ]
  C_CLASS = ["Name contains unknown tokens", "Duplicated code"]

  def warning_class
    w = warnings
    if w.empty?
      nil
    elsif (w & A_CLASS).present?
      'A'
    elsif (w - C_CLASS).empty?
      'C'
    else
      'B'
    end
  end


  def valid?
    warnings.empty?
  end



  # Intermediate fields

  FIELDS = ActiveSupport::OrderedHash[
    :is_manual_s  , 'Корректировка'        ,
    :duration     , 'Длительность'         ,
    :author_stat  , 'Кол-во авторов'       ,
    :author1      , 'Автор 1'              ,
    :author2      , 'Автор 2'              ,
    :author3      , 'Автор 3'              ,
    :author4      , 'Автор 4'              ,
    :author5      , 'Автор 5'              ,
    :citizenship_s, 'Подданство'           ,
    :occupation_s , 'Профессия'            ,
    :position_s   , 'Сословие/чин'         ,
    :location_s   , 'Местоположение'       ,
    :category_s   , 'Отрасль производства' ,
    :cert_num     , '№ свидетельства'      ,
    :date_range   , 'Крайние даты'         ,
    :end_year     , 'Дата окончания'       ,
    :code         , 'Архивный шифр'        ,
    :title        , 'Заголовок'            ,
    :warnings_s   , 'Проблемы'             ,
  ]

  def is_manual
    false
  end

  def is_manual_s
    nil
  end

  include Authors

  def to_row
    FIELDS.keys.map do |field|
      send field
    end
  end



  # YAML fields

  def categories_dbg
    "\n" + category_scores.map do |score, category|
      [score.round(4), category.to_s].join(' ')
    end.join("\n")
  end
  memoize :categories_dbg

  def subject_tokens_yaml
    subject_tokens.map(&:to_yaml)
  end

  def authors_yaml
    authors.map(&:to_yaml)
  end

  SPEC_FIELDS = %i{
    code
    title
    cert_num
    date_range
    end_year
    object
    subject
    subject_tokens_yaml
    duration
    authors_yaml
  }

  def to_spec
    {
      :input => full_str,
      :output => Hash[SPEC_FIELDS.map{ |field| [field, send(field)] } ]
    }
  end
  memoize :to_spec



  include FinalFields

end



class Titles

  include Enumerable
  extend Forwardable
  def_delegators :@titles, :each, :to_a, :sample, :size
  attr_reader :titles
  attr_reader :classifier_examples, :classifier_categories

  def initialize
    @titles = []
    @current_title = nil
    @classifier_examples = []
    @current_classifier_example = nil
    @classifier_categories = Hash.new
  end

  TITLE_END_REGEP = Title::CODE_REGEX

  def next_title
    @current_title = nil
  end

  def current_title
    @current_title ||= Title.new.tap { |t| @titles.push(t) }
  end

  def parse_line(line)
    line.strip!
    return if line.blank?

    current_title.parse_line(line)
    next_title if TITLE_END_REGEP.match(line)
  end


  def add_manual_title(title_hash)
    manual_title = ManualTitle.from_hash(title_hash, classifier_categories)
    indexes = titles.each_index.select{ |i| titles[i].code == manual_title.code}
    if indexes.empty?
      manual_title.warn "Unknown manual title"
      titles.push manual_title
    elsif indexes.many?
      manual_title.warn "Duplicated code"
      titles.push manual_title
    else
      titles[indexes.first] = manual_title
    end
  end


  def next_classifier_example
    @current_classifier_example = nil
  end

  def current_classifier_example
    @current_classifier_example ||=
      ClassifierExample.new(classifier_categories).tap do |t|
        @classifier_examples.push(t)
      end
  end
  CLASSIFIER_EXAMPLE_START_REGEXP = Regexp.new('^\s*ргиа', Regexp::IGNORECASE)

  def parse_classifier_example_line(line)
    line.strip!
    return if line.blank?

    next_classifier_example if CLASSIFIER_EXAMPLE_START_REGEXP.match(line)
    current_classifier_example.parse_line(line)
  end


  def parse_category_line(line)
    Category.parse(line).tap do |category|
      classifier_categories[category.number] = category
    end
  end

  def classified_titles
    @classified_titles ||=
      begin
        t_hash = titles.reject(&:is_manual).map{ |t| [t.code, t] }.to_h
        classifier_examples.map do |example|
          title = t_hash[example.code]
          if title.nil?
            puts "Unknown example: #{example.code}"
          else
            title.category = example.category
          end
          title
        end.compact
      end
  end

  def classify(classifier)
    classifier.train(classified_titles)
    classified = Parallel.map(titles, :progress => "Classifying") do |title|
      classifier.classify(title) if title.needs_classification?
      title
    end
    titles.replace classified
    titles.each{ |t| t.category.try{ |c| c.set_parents(classifier_categories) } }
  end

  def evaluate_classifier(classifier)
    control_ratio = 0.3
    train, control = classified_titles.partition{ rand > control_ratio }
    classifier.train(train)
    control = Parallel.map(control, :progress => "Classifying") do |title|
      classifier.classify(title)
      title
    end
    correct = control.count(&:classified_correctly?)
    correct_p = (correct.to_f/control.size).round(2) * 100
    puts "Correctly classified records #{correct_p}%"
  end

  def invalid_titles
    @duplicated_code ||= titles
      .group_by(&:code).map(&:second).reject(&:one?).flatten
      .each{ |t| t.warn "Duplicated code" }
    titles.reject(&:valid?)
  end

  def with_worst_category_scores(n)
    titles
    .select(&:needs_classification?)
    .sort_by(&:category_confidence_score).first(n)
  end

  def categories_stats
    s = Hash.new(0)
    classifier_categories.values.each { |cat| s[cat] = 0 }
    titles
      .map{ |t| t.category || Category.nil_category }
      .each { |cat| s[cat] += 1 }
    s.to_a
  end

  def stats
    {
      "Total records" => titles.size,
      "Invalid records" => invalid_titles.size
    }
  end
end
