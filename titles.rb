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



class Title

  extend Memoist

  def warnings
    @warnings = []
    validate
    @warnings
  end
  memoize :warnings

  def warnings_s
    warnings.join(', ')
  end

  def warn(msg)
    @warnings << msg
    self
  end

  # FIELDS = ActiveSupport::OrderedHash[
  #   :author_name        , 'Имя автора изобретения',
  #   :author_patronymic  , 'Отчество автора изобретения',
  #   :author             , 'Фамилия автора изобретения',
  #   :author_initials    , 'Инициалы автора изобретения',
  #   :trustee_name       , 'Имя доверенного лица',
  #   :trustee_patronymic , 'Отчество доверенного лица',
  #   :trustee_surname    , 'Фамилия доверенного лица',
  #   :trustee_initials   , 'Инициалы доверенного лица',
  #   :title              , 'Заголовок',
  #   :cert_num           , '№ свидетельства',
  #   :date_range         , 'Крайние даты',
  #   :end_year           , 'Дата окончания',
  #   :code               , 'Архивный шифр',
  #   :notes              , 'Замечания',
  #   :tags_str           , 'Классификаторы',
  # ]


  FIELDS = ActiveSupport::OrderedHash[
    :duration     , 'Длительность'         ,
    :author_stat  , 'Кол-во авторов'       ,
    :company_name , 'Имя компании'         ,
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
    :stripped_subject_with_authors, 'Очищенный заголовок',
    :title        , 'Заголовок'            ,
    # :warnings_s   , 'Проблемы'             ,
  ]


  attr_reader :lines

  def initialize
    @lines = []
  end

  def parse_line(line)
    @lines << line
  end


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


  def confidence_score
    scores = category_scores.take(2).map(&:first)
    scores.first - scores.last
  end
  memoize :confidence_score


  def needs_classification?
    @category.nil? && object.present?
  end


  CODE_REGEX = /^(ргиа\.?\s*)?ф\.?\s*\d+ .*? $/xi
  def code
    CODE_REGEX.match(full_str) do |m|
      return m[0].sub(/[\s.]*$/, '')
    end
  end
  memoize :code


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
      [\p{P}\s]*?
      (\d+ \s* \p{Alpha}+ \s*)? (?<end_year>\d{4})
    )
    [\s.]*
    $
  /xui
  def dates
    DATES_REGEX.match(full_str).to_h
  end
  memoize :dates


  def cert_num
    cert_num_parens
  end


  CERT_NUM_PARENS_REGEX = /
    \(\s* (?:привилегия|патент) .*? (\d+) \)[\s.]*
  /xi

  def cert_num_parens
    CERT_NUM_PARENS_REGEX.match(full_str) do |m|
      return m[1]
    end
  end
  memoize :cert_num_parens


  def author_stat
    author_count = 0
    company_count = 0
    authors.each do |a|
      if a.kind_of? Person
        author_count += 1
      else
        company_count += 1
      end
    end
    "#{company_count + author_count} C#{company_count} A#{author_count}"
  end


  (1..5).each do |i|
    define_method("author#{i}") do
      authors[i - 1].try(:full_name)
    end
  end

  # def citizenship
  #   citizenship = parsed_subject_tokens[:citizenship].to_a
  #   if citizenship.empty?
  #     ['Российский подданный']
  #   else
  #     citizenship
  #   end
  # end

  # def citizenship_s
  #   citizenship.join(', ')
  # end

  # def occupation
  #   parsed_subject_tokens[:occupation].to_a
  # end

  # def occupation_s
  #   occupation.join(', ')
  # end

  # def position
  #   parsed_subject_tokens[:position].to_a
  # end

  # def position_s
  #   position.join(', ')
  # end

  # def location
  #   parsed_subject_tokens[:location].to_a
  # end

  # def location_s
  #   location.join(', ')
  # end


  def subject_tokens
    SubjectTokenizer.new(parsed_title[:subject].to_s).tokenize
  end
  memoize :subject_tokens


  def authors
    AuthorParser.new(subject_tokens).parse
  end
  memoize :authors


  def subject
    parsed_title[:subject]
  end


  def object
    parsed_title[:object].try{ |t| t.gsub(/s+/, ' ')}
  end
  memoize :object


  def duration
    parsed_title[:duration].try{ |t| t.strip }
  end
  memoize :duration


  PARSED_TITLE_REGEXES = [
    /
      ^
      дело\sо\sвыдаче\s
      (привилегии[\p{p}\p{z}]+)?
      (?<duration>на\s\d+\s?(год|года|лет)\s)?
      (привилегии[\p{p}\p{z}]+)?
      (?<subject>.*?)
      (\s|,)(?:на)\s(?!\d+\s?(год|года|лет)\s)
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
    PARSED_TITLE_REGEXES.each do |regex|
      m = regex.match(title)
      next if m.nil?
      return m.to_h.tap do |h|
        h[:subject] += h[:subject_company] if h[:subject_company].present?
      end
    end
    return {}
  end
  memoize :parsed_title


  def title
    lines.first
      .sub(CERT_NUM_PARENS_REGEX, '')
      .sub(/[\s.]*$/, '')
  end
  memoize :title


  def full_str
    @full_str ||= @lines.join("\n").squeeze(' ')
  end
  memoize :full_str


  def validate
    validate_line_count
    validate_parsed_title
    validate_authors
    validate_citizenship
  end


  def validate_authors
    # warn "No authors parsed" if authors.empty? && company_name.blank?
    # warn "Suspicious author count" if authors.count > 3
  end


  def validate_citizenship
    warn "Unknown citizenship" if citizenship.include? :unknown
  end


  def validate_line_count
    warn "Suspicious line count" unless lines.count.in? 2..4
  end

  def validate_parsed_title
    warn "Can't parse title" if title.present? &&title.present? && parsed_title.size == 0
  end


  def valid?
    warnings.empty?
  end

  def suspicious?
    subject.present? && (!authors.count.between?(1,4) || authors.any?(&:suspicious?))
  end


  def to_row
    FIELDS.keys.map do |field|
      send field
    end
  end
  memoize :to_row

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

end



class Titles

  include Enumerable
  extend Forwardable
  def_delegators :@titles, :each, :to_a, :sample, :size
  def_delegators :titles_hash, :[], :values_at
  attr_reader :titles
  attr_reader :classifier_examples, :classifier_categories

  def initialize
    @titles = []
    @current_title = nil
    @classifier_examples = []
    @current_classifier_example = nil
    @classifier_categories = Hash.new
  end

  def titles_hash
    @titles_hash ||= Hash[titles.map{ |t| [t.code, t]}]
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
    @classified_titles ||= classifier_examples.map do |example|
      title = self[example.code]
      if title.nil?
        puts "Unknown example: #{example.code}"
      else
        title.category = example.category
      end
      title
    end.compact
  end

  def classify(classifier)
    classifier.train(classified_titles)
    classified = Parallel.map(titles, :progress => "Classifying") do |title|
      classifier.classify(title) if title.needs_classification?
      title
    end
    titles.replace classified
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
    titles.reject(&:valid?)
  end

  def suspicious
    titles.select(&:suspicious?)
  end

  def with_worst_category_scores(n)
    titles
    .select(&:needs_classification?)
    .sort_by(&:confidence_score).first(n)
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
