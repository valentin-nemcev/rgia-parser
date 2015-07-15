require 'active_support'
require 'active_support/core_ext'

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
    # categories + citizenship
    citizenship
  end

  def category=(cat)
    @category = cat
  end

  def category
    @category || categories.first
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


  def confidence_score
    scores = category_scores.take(2).map(&:first)
    scores.first - scores.last
  end


  def needs_classification?
    @category.nil? && object.present?
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
    parsed_title[:object].try{ |t| t.gsub(/s+/, ' ')}
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

  def categories_dbg
    "\n" + category_scores.map do |score, category|
      [score.round(4), category.to_s].join(' ')
    end.join("\n")
  end

  def record_str_debug
    [:object, :categories_dbg].map do |field|
      value = send field
      next if value.nil?
      [field.to_s.ljust(12), value].join(': ')
    end.compact.join("\n")
  end

  def to_spec
    spec_fields = FIELDS.keys - [:notes] + [:subject, :object]
    {
      :input => full_str,
      :output => Hash[spec_fields.map{ |field| [field, send(field)] } ]
    }
  end

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

  def [](code)
    @titles_hash ||= Hash[titles.map{ |t| [t.code, t]}]
    @titles_hash[code]
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
    Category.new(line).tap do |category|
      classifier_categories[category.number] = category
    end
  end

  def classify(classifier)
    classifier_examples.each do |example|
      title = self[example.code]
      if title.nil?
        puts "Unknown example: #{example.code}"
      else
        title.category = example.category
      end
    end
    classified = Parallel.map(titles, :progress => "Classifying") do |title|
      classifier.classify(title) if title.needs_classification?
      title
    end
    titles.replace classified
  end

  def invalid_titles
    titles.reject(&:valid?)
  end

  def with_worst_category_scores(n)
    titles
    .select(&:needs_classification?)
    .sort_by(&:confidence_score).first(n)
  end

  def stats
    {
      "Total records" => titles.size,
      "Invalid records" => invalid_titles.size
    }
  end
end
